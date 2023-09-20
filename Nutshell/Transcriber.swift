//
//  Transcriber.swift
//  Nutshell
//
//  Created by Laurin Brandner on 02.06.23.
//

import Foundation
import AVFoundation
import ScreenCaptureKit
import Combine
import SwiftWhisper
import AudioKit


private let sampleRate = 16000

class Transcriber: NSObject, ObservableObject, SCStreamDelegate, SCStreamOutput {
    
    var recording = false
    
    private var whisperHandler: WhisperHandler?
    private var whisper: Whisper?

    @Published private(set) var transcript = [String]()
    
    private var audioEngine = AVAudioEngine()
    private var audioBuffer = [Float]()
    private var lhs = [Float]()
    private var processingTimer: Timer?
    private var lastProcessed = 0
    private var isRecording = true
    private var currentPos = 0
    private var timestamps = [(0.0, 0.0)]
    private(set) var uuid = UUID()
    private let documentsPath = NSSearchPathForDirectoriesInDomains(.documentDirectory, .userDomainMask, true)[0]
    private let fileManager = FileManager.default

    
    
    override init (){
        super.init()
        whisper = Whisper(fromFileURL: URL(fileURLWithPath: "/Users/jakubkotal/Downloads/ggml-tiny.bin"))
        whisperHandler = WhisperHandler()
        whisper?.delegate = whisperHandler
        
        whisperHandler?.updateText = { [weak self] res in
            DispatchQueue.main.async {
                self?.transcript = res.0
                self?.timestamps = res.1
                
                
                
                for (time, num) in zip(res.1, 0..<res.1.count){
                    let url = URL(fileURLWithPath: self!.documentsPath).appendingPathComponent("\(self!.uuid.uuidString)/\(num).wav")
                    self!.saveToWavFile(file: Array((self?.audioBuffer[Int(time.0*Double(sampleRate))...Int(time.1*Double(sampleRate))])!), path: url)
                }
            }
        }
    }
    
    func updateAvailableContent() {
        Task {
            do {
//                self.availableContent = try await SCShareableContent.current
            }
            catch {
                print(error)
            }
//            assert(self.availableContent?.displays.isEmpty != nil, "There needs to be at least one display connected")
        }
    }
    
    func requestPermissions() {
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = "Nutshell needs permissions!"
            alert.informativeText = "Nutshell needs screen recording permissions, even if you only intend on recording audio."
            alert.addButton(withTitle: "Open Settings")
            alert.addButton(withTitle: "No thanks, quit")
            alert.alertStyle = .informational
            if alert.runModal() == .alertFirstButtonReturn {
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
            }
            NSApp.terminate(self)
        }
    }
    
    func startRecording() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in  // Move to a background thread
            self?.transcript = [String]()
            self?.whisperHandler?.text = [String]()
            self?.currentPos = 0
            self?.audioBuffer = []
            self?.whisperHandler?.time = 0.0
            self?.whisperHandler?.timestamps = [(Double, Double)]()
            self?.uuid = UUID()
            let url = URL(fileURLWithPath: self!.documentsPath).appendingPathComponent("\(self!.uuid.uuidString)")
            do {
                try self?.fileManager.createDirectory(at: url,
                                                withIntermediateDirectories: true,
                                                attributes: nil)
            } catch {
                print("Error creating directory: \(error)")
            }
            
            let inputNode = self?.audioEngine.inputNode
            let inputFormat = inputNode?.outputFormat(forBus: 0)
            
            // Setup audio converter to convert to PCM with a single channel and sample rate of 44100
            let audioConverter = AVAudioConverter(from: inputFormat!, to: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!)
            
            inputNode?.installTap(onBus: 0, bufferSize: 1600, format: inputFormat) { (buffer, when) in
                let pcmBuffer = AVAudioPCMBuffer(pcmFormat: AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!, frameCapacity: 1600)!
                
                let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                    outStatus.pointee = AVAudioConverterInputStatus.haveData
                    return buffer
                }
                
                var error: NSError?
                audioConverter?.convert(to: pcmBuffer, error: &error, withInputFrom: inputBlock)
                
                if let channelData = pcmBuffer.floatChannelData?[0] {
                    self?.audioBuffer.append(contentsOf: Array(UnsafeBufferPointer(start: channelData, count: Int(pcmBuffer.frameLength))))
                }
            }
            
            do {
                try self?.audioEngine.start()
            } catch {
                print("Could not start audio engine: \(error)")
            }
        }
        self.isRecording = true
        
        Task { [weak self] in // Moved to a Task to run the asynchronous function
            do {
                try await self?.process()
            } catch {
                print("An error occurred while processing: \(error)")
            }
        }
    
    }

    
    func stopRecording() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        self.isRecording = false
    }
    
    private func saveToWavFile(file: [Float], path: URL) {
        // Create AVAudioFormat
        let audioFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 1, interleaved: false)!
        
        // Create AVAudioPCMBuffer
        let pcmBuffer = AVAudioPCMBuffer(pcmFormat: audioFormat, frameCapacity: AVAudioFrameCount(file.count))!
        pcmBuffer.frameLength = AVAudioFrameCount(file.count)
        
        // Copy data to pcmBuffer
        let channelData = pcmBuffer.floatChannelData![0]
        for i in 0..<file.count {
            channelData[i] = file[i]
        }
                
        do {
            let audioFile = try AVAudioFile(forWriting: path, settings: audioFormat.settings)
            try audioFile.write(from: pcmBuffer)
        } catch {
            print("Error while saving to wav file: \(error)")
        }
    }
    
    private func process() async{
        while self.isRecording {
            let sec = 5
            
            if self.audioBuffer.count > sec*sampleRate {
                self.currentPos = self.audioBuffer.count-(sec*sampleRate)
                let analyse = Array(self.audioBuffer.suffix(sec*sampleRate))
                self.whisperHandler?.time = Double(self.currentPos)/Double(sampleRate)
                _ = try! await self.whisper!.transcribe(audioFrames: analyse)
            }
        }
    }


}
