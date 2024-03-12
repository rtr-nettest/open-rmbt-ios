//
//  Keychain.swift
//  RMBT
//
//  Created by Jiri Urbasek on 3/12/24.
//  Copyright © 2024 appscape gmbh. All rights reserved.
//

import Foundation
import KeychainAccess

final class KeychainHelper {
    private static let uuidKeychain = Keychain(service: "at.netztest.app.ios.keychain").accessibility(.whenUnlockedThisDeviceOnly)

    public class func clearStoredUUID(uuidKey: String?) {
        if let uuidKey {
            try? uuidKeychain.remove(uuidKey)
        }
    }

    public class func storeNewUUID(uuidKey: String, uuid: String) {
        try? uuidKeychain.set(uuid, key: uuidKey)
    }

    public class func checkStoredUUID(uuidKey: String) -> String? {
        let unsecureUUID = UserDefaults.appDefaults.object(forKey: uuidKey) as? String
        if let unsecureUUID {
            storeNewUUID(uuidKey: uuidKey, uuid: unsecureUUID)
            UserDefaults.clearStoredUUID(uuidKey: uuidKey)
        }
        return unsecureUUID ?? (try? uuidKeychain.getString(uuidKey))
    }
}

private extension UserDefaults {
    class func clearStoredUUID(uuidKey: String?) {
        if let uuidKey = uuidKey {
            UserDefaults.appDefaults.removeObject(forKey: uuidKey)
            UserDefaults.appDefaults.synchronize()
        }
    }
}
