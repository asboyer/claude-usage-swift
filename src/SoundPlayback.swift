import AppKit
import Foundation

func playClicks(
    count: Int,
    soundName: String,
    delay: TimeInterval = 0.15,
    completion: (() -> Void)? = nil
) {
    guard count > 0 else {
        completion?()
        return
    }

    if let sound = NSSound(named: NSSound.Name(soundName)) {
        sound.play()
    }

    if count > 1 {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            playClicks(count: count - 1, soundName: soundName, delay: delay, completion: completion)
        }
    } else {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
}

func playAlarmBursts(
    bursts: Int = 3,
    clicksPerBurst: Int = 5,
    soundName: String,
    checkMuted: @escaping () -> Bool,
    completion: (() -> Void)? = nil
) {
    guard bursts > 0 else {
        completion?()
        return
    }

    if checkMuted() {
        completion?()
        return
    }

    playClicks(count: clicksPerBurst, soundName: soundName) {
        if bursts > 1 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                playAlarmBursts(
                    bursts: bursts - 1,
                    clicksPerBurst: clicksPerBurst,
                    soundName: soundName,
                    checkMuted: checkMuted,
                    completion: completion
                )
            }
        } else {
            completion?()
        }
    }
}
