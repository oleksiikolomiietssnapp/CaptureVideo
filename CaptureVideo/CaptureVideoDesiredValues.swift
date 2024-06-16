//
//  CaptureVideoDesiredValues.swift
//  CaptureVideo
//
//  Created by Oleksii Kolomiiets on 17.06.2024.
//

import AVFoundation

final class CaptureVideoDesiredValues {
    static let fps: Int = 60
    static let preset: AVCaptureSession.Preset = .hd4K3840x2160

    static var presetDescription: String {
        let prefix: String
        
        switch preset {
        case .hd1920x1080, .hd1280x720:
            prefix = "hd"
        case .hd4K3840x2160:
            prefix = "hd4K"
        case .vga640x480:
            prefix = "vga"
        case .cif352x288:
            prefix = "cif"
        case .iFrame960x540, .iFrame1280x720:
            prefix = "iFrame"
        default:
            prefix = ""
        }
        
        return prefix + "\(width)x\(height)"
    }

    static var width: Int32 {
        switch preset {
        case .hd1920x1080:
            return 1920
        case .hd4K3840x2160:
            return 3840
        case .hd1280x720:
            return 1280
        case .vga640x480:
            return 640
        case .cif352x288:
            return 352
        case .iFrame960x540:
            return 960
        case .iFrame1280x720:
            return 1280
        default:
            return 1280
        }
    }

    static var height: Int32 {
        switch preset {
        case .hd1920x1080:
            return 1080
        case .hd4K3840x2160:
            return 2160
        case .hd1280x720:
            return 720
        case .vga640x480:
            return 480
        case .cif352x288:
            return 288
        case .iFrame960x540:
            return 540
        case .iFrame1280x720:
            return 720
        default:
            return 720
        }
    }
}
