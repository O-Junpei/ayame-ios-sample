import UIKit

import WebRTC
import Starscream
import SwiftyJSON

class ChatViewController: UIViewController {

    var websocket: WebSocket! = nil
    var websocketUri: String!

    var cameraPreview: RTCCameraPreviewView!
    var remoteVideoView: RTCEAGLVideoView!
    var peerConnectionFactory: RTCPeerConnectionFactory! = nil
    var audioSource: RTCAudioSource?
    var videoSource: RTCAVFoundationVideoSource?
    var peerConnection: RTCPeerConnection! = nil
    var remoteVideoTrack: RTCVideoTrack?

    var callBtn: UIButton!
    var hangUpBtn: UIButton!
    var closeBtn: UIButton!

    init(uri: String, roomName: String) {
        super.init(nibName: nil, bundle: nil)
        websocketUri = uri + roomName
    }

    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        if peerConnection != nil {
            hangUp()
        }
        audioSource = nil
        videoSource = nil
        peerConnectionFactory = nil
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white

        remoteVideoView = RTCEAGLVideoView()
        remoteVideoView.delegate = self
        remoteVideoView.backgroundColor = .white
        view.addSubview(remoteVideoView)

        cameraPreview = RTCCameraPreviewView()
        view.addSubview(cameraPreview)

        // RTCPeerConnectionFactoryの初期化
        peerConnectionFactory = RTCPeerConnectionFactory()
        startVideo()

        // WebSocketの初期化
        websocket = WebSocket(url: URL(string: websocketUri)!)
        websocket.delegate = self
        websocket.connect()

        // Initialize Call Button
        callBtn = UIButton()
        callBtn.backgroundColor = UIColor(named: "call-green")
        callBtn.addTarget(self, action: #selector(callBtnOnTap), for: .touchUpInside)
        callBtn.layer.masksToBounds = true
        callBtn.setImage(UIImage(named: "call"), for: .normal)
        view.addSubview(callBtn)

        // Initialize Call Button
        hangUpBtn = UIButton()
        hangUpBtn.backgroundColor = UIColor(named: "call-red")
        hangUpBtn.addTarget(self, action: #selector(hangUpBtnOnTap), for: .touchUpInside)
        hangUpBtn.layer.masksToBounds = true
        hangUpBtn.setImage(UIImage(named: "call-end"), for: .normal)
        view.addSubview(hangUpBtn)

        // Initialize Close Button
        closeBtn = UIButton()
        closeBtn.backgroundColor = .lightGray
        closeBtn.setTitle("←", for: .normal)
        closeBtn.setTitleColor(.white, for: .normal)
        closeBtn.titleLabel?.font = UIFont.boldSystemFont(ofSize: 24)
        closeBtn.addTarget(self, action: #selector(closeBtnOnTap), for: .touchUpInside)
        view.addSubview(closeBtn)
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.frame.width
        let height = view.frame.height
        let buttonSize: CGFloat = 80
        let previewSize = CGSize(width: 60, height: 100)
        let margin: CGFloat = 12
        let sideMargin: CGFloat = 28
        let topSafeAreaHeight = view.safeAreaInsets.top
        let bottomSafeAreaHeight = view.safeAreaInsets.bottom

        closeBtn.frame = CGRect(x: sideMargin, y: topSafeAreaHeight, width: 48, height: 48)
        closeBtn.layer.cornerRadius = 24

        cameraPreview.frame = CGRect(x: width - previewSize.width - sideMargin, y: topSafeAreaHeight, width: previewSize.width, height: previewSize.height)

        hangUpBtn.frame = CGRect(
            x: sideMargin,
            y: height - (buttonSize + bottomSafeAreaHeight + margin),
            width: buttonSize, height: buttonSize)
        hangUpBtn.layer.cornerRadius = buttonSize / 2

        callBtn.frame = CGRect(
            x: width - (buttonSize + sideMargin),
            y: height - (buttonSize + bottomSafeAreaHeight + margin),
            width: buttonSize, height: buttonSize)
        callBtn.layer.cornerRadius = buttonSize / 2
    }

    // MARK: Button Actions
    @objc func callBtnOnTap() {
        print("basicButtonBtnClicked")
        // Connectボタンを押した時
        if peerConnection == nil {
            log("make Offer")
            makeOffer()
        } else {
            log("peer already exist.")
        }
    }

    @objc func hangUpBtnOnTap() {
        hangUp()
    }

    @objc func closeBtnOnTap() {
        hangUp()
        websocket.disconnect()
        navigationController?.popToRootViewController(animated: true)
    }

    func setAnswer(_ answer: RTCSessionDescription) {
        if peerConnection == nil {
            log("peerConnection NOT exist!")
            return
        }
        // 受け取ったSDPを相手のSDPとして設定
        self.peerConnection.setRemoteDescription(answer,
            completionHandler: {
                (error: Error?) in
                if error == nil {
                    self.log("setRemoteDescription(answer) succsess")
                } else {
                    self.log("setRemoteDescription(answer) ERROR: " + error.debugDescription)
                }
            })
    }

    func hangUp() {
        if peerConnection != nil {
            if peerConnection.iceConnectionState != RTCIceConnectionState.closed {
                peerConnection.close()
                let jsonClose: JSON = [
                    "type": "close"
                ]
                log("sending close message")
                websocket.write(string: jsonClose.rawString()!)
            }
            remoteVideoTrack = nil
            peerConnection = nil
            log("peerConnection is closed.")
        }
    }

    func sendIceCandidate(_ candidate: RTCIceCandidate) {
        log("---sending ICE candidate ---")
        let jsonCandidate: JSON = [
            "type": "candidate",
            "ice": [
                "candidate": candidate.sdp,
                "sdpMLineIndex": candidate.sdpMLineIndex,
                "sdpMid": candidate.sdpMid!
            ]
        ]
        let message = jsonCandidate.rawString()!
        log("sending candidate=" + message)
        websocket.write(string: message)
    }

    func sendSDP(_ desc: RTCSessionDescription) {
        log("---sending sdp ---")
        let jsonSdp: JSON = [
            "sdp": desc.sdp, // SDP本体
            "type": RTCSessionDescription.string(
                for: desc.type) // offer か answer か
        ]
        // JSONを生成
        let message = jsonSdp.rawString()!
        log("sending SDP=" + message)
        websocket.write(string: message)
    }

    func makeOffer() {
        // PeerConnectionを生成
        peerConnection = prepareNewConnection()
        // Offerの設定 今回は映像も音声も受け取る
        let constraints = RTCMediaConstraints(
            mandatoryConstraints: [
                "OfferToReceiveAudio": "true",
                "OfferToReceiveVideo": "true"
            ], optionalConstraints: nil)
        let offerCompletion = {
            (offer: RTCSessionDescription?, error: Error?) in
            // Offerの生成が完了した際の処理
            if error != nil { return }
            self.log("createOffer() succsess")

            let setLocalDescCompletion = { (error: Error?) in
                // setLocalDescCompletionが完了した際の処理
                if error != nil { return }
                self.log("setLocalDescription() succsess")
                // 相手に送る
                self.sendSDP(offer!)
            }
            // 生成したOfferを自分のSDPとして設定
            self.peerConnection.setLocalDescription(offer!,
                completionHandler: setLocalDescCompletion)
        }
        // Offerを生成
        self.peerConnection.offer(for: constraints,
            completionHandler: offerCompletion)
    }

    func startVideo() {
        // この中身を書いていきます
        // 音声ソースの設定
        let audioSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        // 音声ソースの生成
        audioSource = peerConnectionFactory
            .audioSource(with: audioSourceConstraints)

        // 映像ソースの設定
        let videoSourceConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil, optionalConstraints: nil)
        videoSource = peerConnectionFactory
            .avFoundationVideoSource(with: videoSourceConstraints)

        // 映像ソースをプレビューに設定
        cameraPreview.captureSession = videoSource?.captureSession
    }

    func prepareNewConnection() -> RTCPeerConnection {
        // STUN/TURNサーバーの指定
        let configuration = RTCConfiguration()
        configuration.iceServers = [
            RTCIceServer.init(urlStrings:
                    ["stun:stun.l.google.com:19302"])]
        // PeerConecctionの設定(今回はなし)
        let peerConnectionConstraints = RTCMediaConstraints(
            mandatoryConstraints: nil,
            optionalConstraints: nil)
        // PeerConnectionの初期化
        peerConnection = peerConnectionFactory.peerConnection(
            with: configuration, constraints: peerConnectionConstraints, delegate: self)

        // 音声トラックの作成
        let localAudioTrack = peerConnectionFactory
            .audioTrack(with: audioSource!, trackId: "ARDAMSa0")
        // PeerConnectionからAudioのSenderを作成
        let audioSender = peerConnection.sender(
            withKind: kRTCMediaStreamTrackKindAudio,
            streamId: "ARDAMS")
        // Senderにトラックを設定
        audioSender.track = localAudioTrack

        // 映像トラックの作成
        let localVideoTrack = peerConnectionFactory.videoTrack(
            with: videoSource!, trackId: "ARDAMSv0")
        // PeerConnectionからVideoのSenderを作成
        let videoSender = peerConnection.sender(
            withKind: kRTCMediaStreamTrackKindVideo,
            streamId: "ARDAMS")
        // Senderにトラックを設定
        videoSender.track = localVideoTrack

        return peerConnection
    }

    // MARK: WebSockets
    func setOffer(_ offer: RTCSessionDescription) {
        if peerConnection != nil {
            log("peerConnection alreay exist!")
        }
        // PeerConnectionを生成する
        peerConnection = prepareNewConnection()
        self.peerConnection.setRemoteDescription(offer, completionHandler: { (error: Error?) in
            if error == nil {
                self.log("setRemoteDescription(offer) succsess")
                // setRemoteDescriptionが成功したらAnswerを作る
                self.makeAnswer()
            } else {
                self.log("setRemoteDescription(offer) ERROR: " + error.debugDescription)
            }
        })
    }

    func makeAnswer() {
        log("sending Answer. Creating remote session description...")
        if peerConnection == nil {
            log("peerConnection NOT exist!")
            return
        }
        let constraints = RTCMediaConstraints(mandatoryConstraints: nil, optionalConstraints: nil)
        let answerCompletion = { (answer: RTCSessionDescription?, error: Error?) in
            if error != nil { return }
            self.log("createAnswer() succsess")
            let setLocalDescCompletion = { (error: Error?) in
                if error != nil { return }
                self.log("setLocalDescription() succsess")
                // 相手に送る
                self.sendSDP(answer!)
            }
            self.peerConnection.setLocalDescription(answer!, completionHandler: setLocalDescCompletion)
        }
        // Answerを生成
        self.peerConnection.answer(for: constraints, completionHandler: answerCompletion)
    }

    func addIceCandidate(_ candidate: RTCIceCandidate) {
        if peerConnection != nil {
            peerConnection.add(candidate)
        } else {
            log("PeerConnection not exist!")
        }
    }
}

// MARK: WebSockets
extension ChatViewController: WebSocketDelegate {
    func websocketDidConnect(socket: WebSocketClient) {
        log("WebsocketDidConnect")
    }

    func websocketDidDisconnect(socket: WebSocketClient, error: Error?) {
        log("error: \(String(describing: error?.localizedDescription))")
    }

    func websocketDidReceiveMessage(socket: WebSocketClient, text: String) {
        log("message: \(text)")
        // 受け取ったメッセージをJSONとしてパース

        let jsonMessage = JSON(parseJSON: text)
        let type = jsonMessage["type"].stringValue
        switch (type) {
        case "answer":
            // answerを受け取った時の処理
            log("Received answer ...")
            let answer = RTCSessionDescription(
                type: RTCSessionDescription.type(for: type),
                sdp: jsonMessage["sdp"].stringValue)
            setAnswer(answer)
        case "candidate":
            log("Received ICE candidate ...")
            let candidate = RTCIceCandidate(
                sdp: jsonMessage["ice"]["candidate"].stringValue,
                sdpMLineIndex:
                    jsonMessage["ice"]["sdpMLineIndex"].int32Value,
                sdpMid: jsonMessage["ice"]["sdpMid"].stringValue)
            addIceCandidate(candidate)
        case "offer":
            // offerを受け取った時の処理
            log("Received offer ...")
            let offer = RTCSessionDescription(
                type: RTCSessionDescription.type(for: type),
                sdp: jsonMessage["sdp"].stringValue)
            setOffer(offer)
        case "close":
            log("peer is closed ...")
            hangUp()
        default:
            return
        }
    }

    func websocketDidReceiveData(socket: WebSocketClient, data: Data) {
        log("data.count: \(data.count)")
    }
}

// MARK: PeerConnection
extension ChatViewController: RTCPeerConnectionDelegate, RTCEAGLVideoViewDelegate {
    func peerConnection(_ peerConnection: RTCPeerConnection, didChange stateChanged: RTCSignalingState) {
        // 接続情報交換の状況が変化した際に呼ばれます
        log("PeerConnectionDidChange")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didAdd stream: RTCMediaStream) {
        // 映像/音声が追加された際に呼ばれます
        log("-- peer.onaddstream()")
        DispatchQueue.main.async(execute: { () -> Void in
            // mainスレッドで実行
            if (stream.videoTracks.count > 0) {
                // ビデオのトラックを取り出して
                self.remoteVideoTrack = stream.videoTracks[0]
                // remoteVideoViewに紐づける
                self.remoteVideoTrack?.add(self.remoteVideoView)
            }
        })
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove stream: RTCMediaStream) {
        // 映像/音声削除された際に呼ばれます
        log("PeerConnectionDidRemove")
    }

    func peerConnectionShouldNegotiate(_ peerConnection: RTCPeerConnection) {
        // 接続情報の交換が必要になった際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceConnectionState) {
        // PeerConnectionの接続状況が変化した際に呼ばれます
        var state = ""
        switch (newState) {
        case RTCIceConnectionState.checking:
            state = "checking"
        case RTCIceConnectionState.completed:
            state = "completed"
        case RTCIceConnectionState.connected:
            state = "connected"
        case RTCIceConnectionState.closed:
            state = "closed"
            hangUp()
        case RTCIceConnectionState.failed:
            state = "failed"
            hangUp()
        case RTCIceConnectionState.disconnected:
            state = "disconnected"
        default:
            break
        }
        log("ICE connection Status has changed to \(state)")
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didChange newState: RTCIceGatheringState) {
        // 接続先候補の探索状況が変化した際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didGenerate candidate: RTCIceCandidate) {
        // Candidate(自分への接続先候補情報)が生成された際に呼ばれます
        if candidate.sdpMid != nil {
            sendIceCandidate(candidate)
        } else {
            log("empty ice event")
        }
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didOpen dataChannel: RTCDataChannel) {
        // DataChannelが作られた際に呼ばれます
    }

    func peerConnection(_ peerConnection: RTCPeerConnection, didRemove candidates: [RTCIceCandidate]) {
        // Candidateが削除された際に呼ばれます
    }

    func videoView(_ videoView: RTCEAGLVideoView, didChangeVideoSize size: CGSize) {
        let width = view.frame.width
        let height = view.frame.height

        let videoAspect = size.width / size.height
        let viewAspect = width / height

        //TODO:  後で考える
        if viewAspect > videoAspect {
            videoView.frame.size = CGSize(width: height / videoAspect, height: height)
        } else {
            videoView.frame.size = CGSize(width: width, height: width * videoAspect)
        }
        videoView.center = view.center
        videoView.clipsToBounds = true
    }
}
