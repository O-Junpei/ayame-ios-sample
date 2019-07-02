import UIKit

extension UIViewController {
    func log(_ body: String = "", function: String = #function, line: Int = #line) {
        print("[\(function) : \(line)] \(body)")
    }
}
