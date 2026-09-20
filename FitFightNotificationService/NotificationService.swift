import UIKit
import UserNotifications

final class NotificationService: UNNotificationServiceExtension, URLSessionTaskDelegate {
    private let lock = NSLock()
    private var handler: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var session: URLSession?

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        guard let content = request.content.mutableCopy() as? UNMutableNotificationContent else {
            contentHandler(request.content)
            return
        }
        lock.lock()
        self.handler = contentHandler
        self.content = content
        lock.unlock()
        guard let payload = content.userInfo["fitfight"] as? [String: Any],
              let raw = payload["image_url"] as? String,
              let url = URL(string: raw),
              Self.isAllowedImageURL(url) else {
            finish()
            return
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        let session = URLSession(configuration: configuration, delegate: self, delegateQueue: nil)
        self.session = session
        session.downloadTask(with: url) { [weak self] location, response, _ in
            guard let self else { return }
            defer { self.finish() }
            guard let location,
                  let response = response as? HTTPURLResponse, response.statusCode == 200,
                  let finalURL = response.url, Self.isAllowedImageURL(finalURL),
                  let size = try? location.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                  size <= 8_388_608,
                  let data = try? Data(contentsOf: location),
                  let image = UIImage(data: data),
                  let jpeg = image.jpegData(compressionQuality: 0.8) else { return }
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("post.jpg")
                try jpeg.write(to: file)
                let attachment = try UNNotificationAttachment(identifier: "post", url: file)
                self.lock.lock()
                self.content?.attachments = [attachment]
                self.lock.unlock()
            } catch {
                // The text remains useful when a signed photo expires or cannot be attached.
            }
        }.resume()
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(request.url.map(Self.isAllowedImageURL) == true ? request : nil)
    }

    override func serviceExtensionTimeWillExpire() {
        session?.invalidateAndCancel()
        finish()
    }

    static func isAllowedImageURL(_ url: URL) -> Bool {
        url.scheme == "https" && url.user == nil && url.password == nil
            && (url.port == nil || url.port == 443)
            && ["pvqntpteehdvhqyctwum.supabase.co", "zstzbfocunthczzubggz.supabase.co"].contains(url.host ?? "")
            && url.path.hasPrefix("/storage/v1/object/sign/user-media/")
    }

    private func finish() {
        lock.lock()
        let completion = handler
        let delivered = content
        handler = nil
        lock.unlock()
        if let completion, let delivered { completion(delivered) }
        session?.finishTasksAndInvalidate()
    }
}
