//
//  HistoryItem.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 07.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import ObjectMapper

@objc final public class HistoryItem: BasicResponse {
    
    /// ONT
    public var jpl:VoipTest?

    ///
    public var testUuid: String?

    public var openTestUuid: String?

    ///
    public var time: UInt64?

    ///
    public var timeZone: String?

    ///
    public var timeString: String?

    ///
    public var qosResultAvailable = false

    ///
    public var speedDownload: String?

    ///
    public var speedUpload: String?

    ///
    public var ping: String?

    ///
    public var pingShortest: String?

    ///
    public var model: String?

    ///
    public var networkType: String?

    ///
    public var speedDownloadClassification: Int?

    ///
    public var speedUploadClassification: Int?

    ///
    public var pingClassification: Int?

    ///
    public var pingShortClassification: Int?
    
    public var networkName: String?
    public var operatorName: String?
    
    public var qosResult: String?
    
    public var loopUuid: String?
    
    public var isCoverageFences: Bool?
    
    public var fencesCount: Int?

    @objc func json() -> [String: Any] {
        return self.toJSON()
    }
    ///
    override public func mapping(map: Map) {
        super.mapping(map: map)
        //
        jpl           <- map["jpl"]
        //

        testUuid           <- map["test_uuid"]
        openTestUuid       <- map["open_test_uuid"]
        time               <- (map["time"], UInt64NSNumberTransformOf)
        timeZone           <- map["time_zone"]
        timeString         <- map["time_string"]
        qosResultAvailable <- map["qos_result_available"]
        speedDownload      <- map["speed_download"]
        speedUpload        <- map["speed_upload"]
        ping               <- map["ping"]
        pingShortest       <- map["ping_shortest"]
        model              <- map["model"]
        networkType        <- map["network_type"]
        speedDownloadClassification <- map["speed_download_classification"]
        speedUploadClassification   <- map["speed_upload_classification"]
        pingClassification          <- map["ping_classification"]
        pingShortClassification     <- map["ping_short_classification"]
        networkName         <- map["network_name"]
        operatorName         <- map["operator"]
        qosResult           <- map["qos_result"]
        loopUuid            <- map["loop_uuid"]
        isCoverageFences    <- map["isCoverageFences"]
        fencesCount         <- map["fencesCount"]
    }
}
