#include "mowser_client.h"

#include <algorithm>
#include <cerrno>
#include <cstring>
#include <filesystem>
#include <fcntl.h>
#include <sys/stat.h>
#include <unistd.h>

namespace mowser {

void Client::remove_reservation(const Download &download) {
    struct stat st {};
    // Remove only our own empty reservation, never a completed file or a file
    // another application has replaced in the meantime.
    if (::lstat(download.path.c_str(), &st) == 0 && st.st_size == 0 &&
        uint64_t(st.st_dev) == download.device && uint64_t(st.st_ino) == download.inode)
        ::unlink(download.path.c_str());
}

void Client::detach() {
    sink_ = nullptr;
    devtools_registration_ = nullptr;
    cancel_dialogs();
    auto pending = std::move(downloads_);
    downloads_.clear();
    for (auto &[id, download] : pending) {
        if (download.callback) download.callback->Cancel();
        remove_reservation(download);
    }
}

void Client::cancel_download(uint32_t id) {
    auto found = downloads_.find(id);
    if (found == downloads_.end()) return;
    auto callback = found->second.callback;
    if (callback) callback->Cancel();
}

bool Client::OnBeforeDownload(CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefDownloadItem> item, const CefString &suggested_name,
    CefRefPtr<CefBeforeDownloadCallback> callback) {
    // Handling the callback ourselves avoids Chrome's download shelf / Save As
    // UI, which has no usable window in this embedded browser. Never auto-open.
    if (!sink_) return true;
    const uint32_t id = item->GetId();
    std::error_code error;
    const std::filesystem::path directory(download_directory_);
    if (directory.is_absolute()) std::filesystem::create_directories(directory, error);
    if (!directory.is_absolute() || error) {
        sink_->sink_download(id, "download", 0, 0, "failed", "Cannot create the Downloads folder.");
        return true;
    }
    std::string name = suggested_name.ToString();
    std::replace(name.begin(), name.end(), '\\', '/');
    name = std::filesystem::path(name).filename().string();
    name.erase(std::remove_if(name.begin(), name.end(), [](unsigned char c) {
        return c < 32 || c == 127;
    }), name.end());
    if (name.empty() || name == "." || name == "..") name = "download";
    if (name.front() == '.') name.front() = '_';
    const std::filesystem::path filename(name);
    Download download;
    for (int attempt = 0; attempt < 10000; ++attempt) {
        const std::string candidate = attempt == 0 ? name :
            filename.stem().string() + " (" + std::to_string(attempt) + ")" + filename.extension().string();
        download.path = (directory / candidate).string();
        const int fd = ::open(download.path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (fd >= 0) {
            struct stat st {};
            ::fstat(fd, &st);
            download.device = st.st_dev;
            download.inode = st.st_ino;
            ::close(fd);
            downloads_[id] = download;
            sink_->sink_download(id, download.path, 0, item->GetTotalBytes(), "downloading", "");
            callback->Continue(download.path, false);
            return true;
        }
        if (errno != EEXIST) break;
    }
    sink_->sink_download(id, name, 0, 0, "failed", "Cannot save in Downloads: " + std::string(std::strerror(errno)));
    return true;
}

void Client::OnDownloadUpdated(CefRefPtr<CefBrowser> browser,
    CefRefPtr<CefDownloadItem> item, CefRefPtr<CefDownloadItemCallback> callback) {
    auto found = downloads_.find(item->GetId());
    // CEF also reports updates before OnBeforeDownload has chosen a path.
    if (found == downloads_.end()) return;
    found->second.callback = callback;
    const Download download = found->second;
    std::string state = "downloading";
    std::string detail;
    if (item->IsComplete()) state = "complete";
    else if (item->IsCanceled()) state = "cancelled";
    else if (item->IsInterrupted()) {
        state = "failed";
        detail = "Download interrupted (" + std::to_string(item->GetInterruptReason()) + "). Try again.";
    }
    if (state != "downloading") {
        downloads_.erase(found);
        if (state != "complete") remove_reservation(download);
    }
    const std::string full_path = item->GetFullPath().empty() ? download.path : item->GetFullPath().ToString();
    if (sink_) sink_->sink_download(item->GetId(), full_path,
        item->GetReceivedBytes(), item->GetTotalBytes(), state, detail);
}

}  // namespace mowser
