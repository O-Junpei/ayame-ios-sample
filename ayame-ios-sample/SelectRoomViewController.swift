import UIKit

class SelectRoomViewController: UIViewController {
    
    private var textField: UITextField!
    private var button: UIButton!
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        view.backgroundColor = .white
        
        // Initialize TextView
        textField = UITextField()
        textField.delegate = self
        textField.textAlignment = .center
        textField.placeholder = "room name"
        textField.clearButtonMode = .whileEditing
        textField.keyboardType = .alphabet
        textField.layer.borderWidth = 0.5
        textField.layer.borderColor = UIColor.gray.withAlphaComponent(0.5).cgColor
        textField.layer.cornerRadius = 8
        view.addSubview(textField)
        
        // Initialize Button
        button = UIButton()
        button.backgroundColor = UIColor.lightGray
        button.layer.cornerRadius = 8
        button.addTarget(self, action: #selector(taped(sender:)), for:.touchUpInside)
        button.setTitle("join room", for: UIControl.State.normal)
        button.setTitleColor(UIColor.white, for: UIControl.State.normal)
        view.addSubview(button)
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        let width = view.frame.width
        let height = view.frame.height
        
        textField.frame.size = CGSize(width: 260, height: 60)
        textField.center.x = width / 2
        textField.center.y = height / 2 - 100
        
        button.frame.size = CGSize(width: 260, height: 60)
        button.center.x = width / 2
        button.center.y = height / 2
    }
    
    //MARK: Button Action
    @objc func taped(sender: UIButton){
        guard let text = textField.text else { return }
        
        var title: String?
        if text.isEmpty {
            title = "Input room name"
        } else if text.utf8.count < 4 {
            title = "Room name must be at least 4 letters"
        }
        
        if let title = title {
            let alert = UIAlertController(title: title, message: "", preferredStyle:  UIAlertController.Style.alert)
            let cancelAction = UIAlertAction(title: "close", style: UIAlertAction.Style.cancel, handler:nil)
            alert.addAction(cancelAction)
            present(alert, animated: true, completion: nil)
            return
        }
        
        textField.resignFirstResponder()
        let vc = ChatViewController(uri: WEBSOCKET_URI,roomName: text)
        navigationController?.pushViewController(vc, animated: true)
    }
}

//MARK: TextView Delegate Methods
extension SelectRoomViewController: UITextFieldDelegate {
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        textField.resignFirstResponder()
        return true
    }
}
