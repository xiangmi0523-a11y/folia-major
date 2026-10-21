import AVFoundation
import UIKit

// 应用入口：打开后台播放用的音频会话，窗口里只放一个加载 Folia 服务端网页的 WebViewController。

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    var window: UIWindow?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
    ) -> Bool {
        // .playback 让锁屏、切到后台、静音键打开时网页里的 <audio> 都继续出声（配合 Info.plist 的 UIBackgroundModes audio）
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            NSLog("[FoliaiOS] 音频会话设置失败: %@", String(describing: error))
        }

        let window = UIWindow(frame: UIScreen.main.bounds)
        window.backgroundColor = Theme.background
        window.rootViewController = WebViewController()
        window.makeKeyAndVisible()
        self.window = window
        return true
    }
}

enum Theme {
    // 和网页版 manifest 的 background_color 一致
    static let background = UIColor(red: 0x09 / 255.0, green: 0x09 / 255.0, blue: 0x0B / 255.0, alpha: 1)
}
