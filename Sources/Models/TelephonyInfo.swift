/*****************************************************************************************************
 * Copyright 2016 SPECURE GmbH
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *   http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 *****************************************************************************************************/

import Foundation
import ObjectMapper

///
class TelephonyInfo: Mappable {

    ///
    var dataState: Int?

    ///
    var networkCountry: String?

    ///
    var networkIsRoaming: Bool?

    ///
    var networkOperator: String?

    ///
    var networkOperatorName: String?

    ///
    var networkSimCountry: String?

    ///
    var networkSimOperator: String?

    ///
    var networkSimOperatorName: String?

    ///
    var phoneType: Int?

    ///
    init() {

    }

    ///
    init(connectivity: RMBTConnectivity) {
        networkOperatorName = connectivity.networkName
    }

    ///
    required init?(map: Map) {

    }

    ///
    func mapping(map: Map) {
        dataState           <- map["data_state"]
        networkCountry      <- map["network_country"]
        networkIsRoaming    <- map["network_is_roaming"]

        networkOperator     <- map["network_operator"]
        networkOperatorName <- map["network_operator_name"]

        networkSimCountry       <- map["network_sim_country"]
        networkSimOperator      <- map["network_sim_operator"]
        networkSimOperatorName  <- map["network_sim_operator_name"]
        phoneType               <- map["phone_type"]
    }
}
