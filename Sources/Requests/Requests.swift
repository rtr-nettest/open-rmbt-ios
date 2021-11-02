//
//  Old_Request.swift
//  rmbt-ios-client
//
//  Created by Tomas Baculák on 10/07/2017.
//
//

import Foundation
import ObjectMapper
import CoreLocation

///
public class MeasurementServerInfoRequest: BasicRequest {
    var geoLocation: GeoLocation?
    
    override public func mapping(map: Map) {
        super.mapping(map: map)
        
        client <- map["client"]
        geoLocation <- map["location"]
    }
}

///
public class HistoryWithQOSRequest: BasicRequest {

    var testUUID: String?
    
    override public func mapping(map: Map) {
        super.mapping(map: map)
        testUUID <- map["test_uuid"]
    }
}
///
public class HistoryWithFiltersRequest: BasicRequest {
    //
    var resultOffset:NSNumber?
    //
    var resultLimit:NSNumber?
    //
    var networks:[String]?
    //
    var devices: [String]?
    
    ///
    override public func mapping(map: Map) {
        super.mapping(map: map)
        
        resultOffset <- map["result_offset"]
        resultLimit <- map["result_limit"]
        networks <- map["network_types"]
        devices <- map["devices"]
    }
}


///
public class GetSyncCodeRequest: BasicRequest {
    
    ///
    override public func mapping(map: Map) {
        super.mapping(map: map)
    }

}

///
public class SyncCodeRequest: BasicRequest {

    var code:String!
    
    ///
    override public func mapping(map: Map) {
        super.mapping(map: map)
        
        code <- map["sync_code"]
    }
}

///
public class IPRequest_Old: BasicRequest {
    
    ///
    var software_Version_Code: String = "6666" // and more than that
//    var plattform:String = ""
    
    ///
    override public func mapping(map: Map) {
        super.mapping(map: map)
        
        software_Version_Code <- map["softwareVersionCode"]
        // there is a bug on the server side that's why double t !!!
        plattform <- map["plattform"]
        
    }
}
///
///
@objc public class SpeedMeasurementRequest_Old: BasicRequest {
    
    
    ///
    var ndt = false
    
    ///
    var anonymous = false
    
    ///
    var time: UInt64?
   
    ///
    @objc public var testCounter: UInt = 0
    
    ///
    @objc public var geoLocation: GeoLocation? 
    
    var measurementTypeFlag = "dedicated"
    
    ///
    var measurementServerId: UInt64?
    
    
    ///
    public override func mapping(map: Map) {
        super.mapping(map: map)
        
        
        ndt         <- map["ndt"]
        anonymous   <- map["anonymous"]
        testCounter <- map["testCounter"]
        
        geoLocation <- map["location"]
        
        time <- map["time"]
        name <- map["name"]
        client <- map["client"]
        
        //
        measurementServerId <- map["measurement_server_id"]
        measurementTypeFlag <- map["measurement_type_flag"]
    }
}

///
public class SettingsRequest: BasicRequest {
    var termsAndConditionsAccepted = false
    var termsAndConditionsAccepted_Version = 0
    
    override public func mapping(map: Map) {
        super.mapping(map: map)
        
        termsAndConditionsAccepted <- map["terms_and_conditions_accepted"]
        termsAndConditionsAccepted_Version <- map["terms_and_conditions_accepted_version"]
    }
}

///
public class CheckSurveyRequest: BasicRequest {
    
    ///
    var clientUuid: String = ""

    ///
    override public func mapping(map: Map) {
        clientUuid <- map["client_uuid"]
    }
}
