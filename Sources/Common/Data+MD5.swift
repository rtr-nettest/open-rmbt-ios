//
//  Data+MD5.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 10.12.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import Foundation
import CryptoKit

extension Data {
    var MD5HexString: String {
        let digest = Insecure.MD5.hash(data: self)

        return digest
            .map { String(format: "%02hhx", $0) }
            .joined()
    }
}

