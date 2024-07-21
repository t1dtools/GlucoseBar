//
//  DispatchTimer.swift
//  NightscoutAPIClient
//
//  Created by Ivan Valkou on 07.01.2020.
//  Copyright © 2020 Ivan Valkou. All rights reserved.
//

import Foundation

final class DispatchTimer {
    let timeInterval: TimeInterval
    let queue: DispatchQueue

    init(timeInterval: TimeInterval, queue: DispatchQueue = .global()) {
        self.timeInterval = timeInterval
        self.queue = queue
    }

    private lazy var timer: DispatchSourceTimer = {
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + timeInterval, repeating: timeInterval)
        timer.setEventHandler(handler: { [weak self] in
            self?.eventHandler?()
        })
        return timer
    }()

    var eventHandler: (() -> Void)?

    private enum State {
        case suspended
        case resumed
    }

    private var state: State = .suspended

    func resume() {
        if state == .resumed {
            return
        }
        state = .resumed
        timer.resume()
    }

    func suspend() {
        if state == .suspended {
            return
        }
        state = .suspended
        timer.suspend()
    }

    deinit {
        timer.setEventHandler {}
        timer.cancel()
        /*
         If the timer is suspended, calling cancel without resuming
         triggers a crash. This is documented here
         https://forums.developer.apple.com/thread/15902
         */
        resume()
        eventHandler = nil
    }
}
