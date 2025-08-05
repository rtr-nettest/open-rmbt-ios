//
//  BackgroundActivityActor.swift
//  RMBT
//
//  Created by Jiri Urbasek on 2025-08-04.
//  Copyright 2025 appscape gmbh. All rights reserved.
//

import CoreLocation
import Foundation

/// Thread-safe manager for CLBackgroundActivitySession with reference counting
/// to support multiple NetworkCoverageViewModel instances
@globalActor
actor BackgroundActivityActor {
    static let shared = BackgroundActivityActor()
    
    private var session: CLBackgroundActivitySession?
    private var refCount = 0
    
    private init() {}
    
    /// Starts background activity session if not already active
    /// Uses reference counting to support multiple clients
    func startActivity() {
        refCount += 1
        if session == nil {
            session = CLBackgroundActivitySession()
        }
    }
    
    /// Stops background activity session when reference count reaches zero
    func stopActivity() {
        refCount = max(0, refCount - 1)
        if refCount == 0 {
            session?.invalidate()
            session = nil
        }
    }
    
    /// Returns whether background activity session is currently active
    func isActive() -> Bool {
        session != nil
    }
}
