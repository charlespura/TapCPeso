import Flutter
import UIKit
import CoreNFC

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate, NFCTagReaderSessionDelegate {
  private var nfcChannel: FlutterMethodChannel?
  private var nfcSession: NFCTagReaderSession?
  private var pendingRead: FlutterResult?
  private var readingTag = false
  private let select = Data([0x00, 0xA4, 0x04, 0x00, 0x0A,
    0xF0, 0x54, 0x41, 0x50, 0x43, 0x50, 0x45, 0x53, 0x4F, 0x01, 0x00])

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "tapcpeso/nfc",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    nfcChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "capabilities":
        result(["reader": NFCTagReaderSession.readingAvailable,
          "sender": false, "enabled": NFCTagReaderSession.readingAvailable])
      case "offer":
        result(FlutterError(code: "NFC_SENDER_UNSUPPORTED",
          message: "iPhone card emulation requires Apple-managed entitlements. Use QR to send.", details: nil))
      case "read":
        guard NFCTagReaderSession.readingAvailable else {
          result(FlutterError(code: "NFC_UNAVAILABLE", message: "NFC reader unavailable. Use QR.", details: nil)); return
        }
        guard self.pendingRead == nil else {
          result(FlutterError(code: "NFC_BUSY", message: "NFC reader already active.", details: nil)); return
        }
        self.pendingRead = result
        self.readingTag = false
        let session = NFCTagReaderSession(pollingOption: .iso14443, delegate: self, queue: .main)
        guard let session = session else {
          self.finish(error: "Could not create NFC session."); return
        }
        self.nfcSession = session
        session.alertMessage = "Hold the top of your iPhone near the unlocked Android sender with Real NFC started."
        session.begin()
      case "stop":
        self.finish(error: "NFC session cancelled.")
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }

  private func finish(payload: String? = nil, error: String? = nil) {
    let callback = pendingRead
    pendingRead = nil
    let session = nfcSession
    nfcSession = nil
    if let error = error {
      session?.invalidate(errorMessage: error)
      callback?(FlutterError(code: "NFC_READ", message: error, details: nil))
    } else {
      session?.alertMessage = "Transfer read. Validating payment in TapCPeso…"
      session?.invalidate()
      callback?(payload)
    }
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
    guard nfcSession === session else { return }
    let callback = pendingRead
    pendingRead = nil
    nfcSession = nil
    callback?(FlutterError(code: "NFC_CANCELLED", message: error.localizedDescription, details: nil))
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard nfcSession === session, !readingTag else { return }
    guard tags.count == 1, case .iso7816(let card) = tags[0] else {
      session.alertMessage = "Present one Android TapCPeso sender."
      session.restartPolling(); return
    }
    readingTag = true
    session.connect(to: tags[0]) { [weak self] error in
      DispatchQueue.main.async {
        guard let self = self, self.nfcSession === session else { return }
        if let error = error { self.finish(error: error.localizedDescription); return }
        guard let command = NFCISO7816APDU(data: self.select) else {
          self.finish(error: "Invalid NFC command."); return
        }
        self.exchange(card, command, session: session) { data in
          guard data.count == 2 else { self.finish(error: "Invalid payment header."); return }
          let bytes = [UInt8](data)
          let size = (Int(bytes[0]) << 8) | Int(bytes[1])
          guard (1...4096).contains(size) else { self.finish(error: "Invalid payment size."); return }
          self.readChunks(card, size: size, collected: Data(), session: session)
        }
      }
    }
  }

  private func exchange(_ card: NFCISO7816Tag, _ command: NFCISO7816APDU,
    session: NFCTagReaderSession, completion: @escaping (Data) -> Void) {
    card.sendCommand(apdu: command) { [weak self] data, sw1, sw2, error in
      DispatchQueue.main.async {
        guard let self = self, self.nfcSession === session else { return }
        guard error == nil, sw1 == 0x90, sw2 == 0x00 else {
          self.finish(error: "NFC interrupted or sender not ready. Retry the same payment or scan QR."); return
        }
        completion(data)
      }
    }
  }

  private func readChunks(_ card: NFCISO7816Tag, size: Int, collected: Data, session: NFCTagReaderSession) {
    guard nfcSession === session else { return }
    if collected.count == size {
      guard let text = String(data: collected, encoding: .utf8) else {
        finish(error: "Invalid transfer text."); return
      }
      finish(payload: text); return
    }
    let offset = collected.count
    let count = min(192, size - offset)
    let command = NFCISO7816APDU(instructionClass: 0x00, instructionCode: 0xB0,
      p1Parameter: UInt8(offset >> 8), p2Parameter: UInt8(offset & 255),
      data: Data(), expectedResponseLength: count)
    exchange(card, command, session: session) { data in
      guard data.count == count else { self.finish(error: "Incomplete transfer. Retry the same payment."); return }
      self.readChunks(card, size: size, collected: collected + data, session: session)
    }
  }
}
