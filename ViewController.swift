import UIKit
import WebKit

/// Root controller: a completely standard UITabBarController.
/// No custom appearance is set anywhere, so when the app is built with the
/// iOS 26 SDK and run on iOS 26+, the tab bar is the default Liquid Glass
/// tab bar; on older iOS versions it falls back to the classic style.
///
/// All tabs share one WKWebView with the Kataomoi Calendar page.
/// - The page's own HTML tab bar is hidden by an injected script.
/// - Tapping a native tab forwards to the page's showTab() via its buttons.
/// - The page reports the active tab, renamed tab labels and hidden tabs
///   back to native, so the bar stays in sync with in-page navigation
///   (e.g. opening the calendar from a person card) and with the page's
///   tab name / visibility settings.
final class MainTabBarController: UITabBarController, UITabBarControllerDelegate,
                                  WKNavigationDelegate, WKDownloadDelegate,
                                  WKScriptMessageHandler {
    private struct TabDef {
        let key: String
        let title: String
        let icon: String
        let selectedIcon: String
    }

    private let defs: [TabDef] = [
        TabDef(key: "home",  title: "ホーム",    icon: "house",           selectedIcon: "house.fill"),
        TabDef(key: "cal",   title: "カレンダー", icon: "calendar",        selectedIcon: "calendar"),
        TabDef(key: "stats", title: "統計",      icon: "chart.bar.xaxis", selectedIcon: "chart.bar.xaxis"),
        TabDef(key: "dash",  title: "ダッシュ",   icon: "square.grid.2x2", selectedIcon: "square.grid.2x2.fill"),
    ]

    private(set) var webView: WKWebView!
    private var shownKeys: [String] = ["home", "cal", "stats", "dash"]
    private var labels: [String: String] = [:]
    private var downloadURL: URL?

    private static let bridgeJS = """
    (function(){
      var style = document.createElement('style');
      style.textContent = '#tab-bar{display:none !important} .app{padding-bottom:24px !important}';
      document.head.appendChild(style);
      window.__nativeSetTab = function(key){
        var b = document.getElementById('ti-' + key);
        if (b) b.click();
      };
      function sync(){
        try {
          var items = [];
          ['home','cal','stats','dash'].forEach(function(k){
            var b = document.getElementById('ti-' + k);
            if (!b) return;
            var label = b.querySelector('.tab-label');
            items.push({
              key: k,
              label: label ? label.textContent.trim() : '',
              shown: getComputedStyle(b).display !== 'none'
            });
          });
          var act = document.querySelector('.section.active');
          var active = act ? act.id.replace('tab-', '') : '';
          var accent = getComputedStyle(document.documentElement).getPropertyValue('--deep').trim();
          window.webkit.messageHandlers.tabSync.postMessage({active: active, items: items, accent: accent});
        } catch(e) {}
      }
      var pending = false;
      function queueSync(){
        if (pending) return;
        pending = true;
        setTimeout(function(){ pending = false; sync(); }, 120);
      }
      new MutationObserver(queueSync).observe(document.body,
        {subtree: true, attributes: true, attributeFilter: ['class', 'style'], characterData: true});
      new MutationObserver(queueSync).observe(document.documentElement,
        {attributes: true, attributeFilter: ['data-theme']});
      window.addEventListener('load', queueSync);
      sync();
    })();
    """

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        view.backgroundColor = UIColor(red: 1.0, green: 0.96, blue: 0.97, alpha: 1.0) // #fff5f8
        tabBar.tintColor = UIColor(hexString: "#c0496d") // default theme accent until the page reports its own
        setupWebView()
        rebuildTabs()
    }

    // MARK: - Web view

    private func setupWebView() {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = .default() // persistent localStorage
        config.defaultWebpagePreferences.allowsContentJavaScript = true
        config.userContentController.add(self, name: "tabSync")
        config.userContentController.addUserScript(
            WKUserScript(source: Self.bridgeJS, injectionTime: .atDocumentEnd, forMainFrameOnly: true))

        webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = self
        webView.translatesAutoresizingMaskIntoConstraints = false

        guard let url = Bundle.main.url(forResource: "index", withExtension: "html") else { return }
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
    }

    fileprivate func attachWebView(to container: UIViewController) {
        if webView.superview !== container.view {
            webView.removeFromSuperview()
            container.view.addSubview(webView)
            NSLayoutConstraint.activate([
                webView.topAnchor.constraint(equalTo: container.view.topAnchor),
                webView.bottomAnchor.constraint(equalTo: container.view.bottomAnchor),
                webView.leadingAnchor.constraint(equalTo: container.view.leadingAnchor),
                webView.trailingAnchor.constraint(equalTo: container.view.trailingAnchor),
            ])
        }
    }

    // MARK: - Tabs

    private func rebuildTabs() {
        let keepKey = (selectedViewController as? TabContainerViewController)?.key
        var controllers: [UIViewController] = []
        for key in shownKeys {
            guard let def = defs.first(where: { $0.key == key }) else { continue }
            let vc = TabContainerViewController(key: key, owner: self)
            vc.tabBarItem = UITabBarItem(
                title: labels[key] ?? def.title,
                image: UIImage(systemName: def.icon),
                selectedImage: UIImage(systemName: def.selectedIcon))
            controllers.append(vc)
        }
        viewControllers = controllers
        if let keepKey, let idx = shownKeys.firstIndex(of: keepKey) {
            selectedIndex = idx
        }
    }

    func tabBarController(_ tabBarController: UITabBarController,
                          shouldSelect viewController: UIViewController) -> Bool {
        if let container = viewController as? TabContainerViewController {
            webView.evaluateJavaScript("window.__nativeSetTab && window.__nativeSetTab('\(container.key)')")
        }
        return true
    }

    // MARK: - Page -> native sync

    func userContentController(_ userContentController: WKUserContentController,
                               didReceive message: WKScriptMessage) {
        guard message.name == "tabSync",
              let body = message.body as? [String: Any] else { return }
        // Follow the page's color theme: the selected tab takes the theme accent.
        if let accent = body["accent"] as? String,
           let color = UIColor(hexString: accent) {
            tabBar.tintColor = color
        }
        let active = body["active"] as? String ?? ""
        var newShown: [String] = []
        if let items = body["items"] as? [[String: Any]] {
            for item in items {
                guard let key = item["key"] as? String else { continue }
                if let label = item["label"] as? String, !label.isEmpty {
                    labels[key] = label
                }
                if (item["shown"] as? Bool) == true {
                    newShown.append(key)
                }
            }
        }
        if !newShown.isEmpty, newShown != shownKeys {
            shownKeys = newShown
            rebuildTabs()
        } else {
            // Refresh titles in case labels were renamed.
            for vc in viewControllers ?? [] {
                guard let container = vc as? TabContainerViewController,
                      let label = labels[container.key] else { continue }
                vc.tabBarItem.title = label
            }
        }
        // Follow in-page navigation unless it targets a non-tab screen (e.g. settings).
        if shownKeys.contains(active),
           let idx = shownKeys.firstIndex(of: active),
           selectedIndex != idx {
            selectedIndex = idx
        }
    }

    // MARK: - Downloads (backup export -> share sheet)

    func webView(_ webView: WKWebView,
                 decidePolicyFor navigationResponse: WKNavigationResponse,
                 decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        let disposition = (navigationResponse.response as? HTTPURLResponse)?
            .value(forHTTPHeaderField: "Content-Disposition") ?? ""
        if disposition.contains("attachment") || !navigationResponse.canShowMIMEType {
            decisionHandler(.download)
        } else {
            decisionHandler(.allow)
        }
    }

    func webView(_ webView: WKWebView,
                 navigationResponse: WKNavigationResponse,
                 didBecome download: WKDownload) {
        download.delegate = self
    }

    func download(_ download: WKDownload,
                  decideDestinationUsing response: URLResponse,
                  suggestedFilename: String,
                  completionHandler: @escaping (URL?) -> Void) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(suggestedFilename)
        try? FileManager.default.removeItem(at: url)
        downloadURL = url
        completionHandler(url)
    }

    func downloadDidFinish(_ download: WKDownload) {
        guard let url = downloadURL else { return }
        let sheet = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        present(sheet, animated: true)
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {}
}

private extension UIColor {
    /// "#c0496d" or "#fff" -> UIColor; nil for anything else.
    convenience init?(hexString: String) {
        var s = hexString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("#") else { return nil }
        s.removeFirst()
        if s.count == 3 { s = s.map { "\($0)\($0)" }.joined() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: CGFloat((v >> 16) & 0xff) / 255,
                  green: CGFloat((v >> 8) & 0xff) / 255,
                  blue: CGFloat(v & 0xff) / 255,
                  alpha: 1.0)
    }
}

/// One tab's content area. The shared web view moves into whichever
/// container is about to appear.
final class TabContainerViewController: UIViewController {
    let key: String
    private weak var owner: MainTabBarController?

    init(key: String, owner: MainTabBarController) {
        self.key = key
        self.owner = owner
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor(red: 1.0, green: 0.96, blue: 0.97, alpha: 1.0) // #fff5f8
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        owner?.attachWebView(to: self)
    }
}
