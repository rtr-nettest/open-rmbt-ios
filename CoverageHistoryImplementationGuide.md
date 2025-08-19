# History Overview Screen Implementation Guide

## Overview
The History Overview Screen displays both regular speed test results and coverage measurement results. Coverage measurements are identified by the `isCoverageFences` and `fencesCount` fields in the history response.

## UI Implementation

### History Row Display Logic

Coverage measurements should be displayed differently from regular speed tests:

#### For Single Coverage Measurement:

The UI of History table cell for Single Coverage Measurement should look like as follows:
┌───────────────────────────────────────────────-------------──────────┐
│ [tab_coverage icon]    [date / time label]               1234 Points │
│                                                                      │
└────────────────────────────────────────────-------------─────────────┘


#### For Coverage Loop (Multiple Related Measurements):

The UI of History table cell for Loop Coverage Measurement should look like as follows:
┌───────────────────────────────────────────────-------------──────────┐
│ [tab_coverage icon]    [date / time label]                       \/  │
│                        "Coverage"                                    │
└────────────────────────────────────────────-------------─────────────┘

Cells are grooped into a loop if they include `loop_uuid` response attribute. Similarly as it is being done for network speed tests.

### Implementation Steps

1. **Detect Coverage Measurements**
   ```swift
   if historyItem.isCoverageFences == true {
       // This is a coverage measurement
       displayCoverageRow(item: historyItem)
   }
   ```

2. **Group Related Measurements**
   - Group measurements by `loop_uuid` if available
   - Single measurement: Show point count
   - Multiple measurements in loop: Show expandable group

3. **Row Content**
Uses existing `RMBTHistoryIndexCell`, but some of the labels will be left empty.

Content which is present: 
   - **Icon**: Use coverage-specific icon ("tab_coverage" icon we already have). Might need to adjust size to fit properly into table row UI
   - **Title**: Show date/time from `time_string`
   - **Subtitle**: "Coverage" for single, "Coverage loop" for grouped
   - **Right Side**: 
     - Single: "`<fencesCount>` Points"
     - Loop: Expand/collapse arrow

4. **Visual Styling**
   - Use existing`RMBTHistoryIndexCell` but less text labels would be needed.
   - Coverage measurements don't show speed/ping values

### Conditional Display Logic

Create new configuration method to configure `RMBTHistoryIndexCell` based of which type it is.
```swift
func configureHistoryCell(with item: HistoryItem) {
    if item.isCoverageFences == true {
        // Coverage measurement
        iconImageView.image = coverageIcon
        titleLabel.text = item.timeString
        
        if item.loopUuid != nil && hasMultipleInLoop {
            subtitleLabel.text = "Coverage loop"
            accessoryView = expandArrow
        } else {
            subtitleLabel.text = "Coverage"
            accessoryView = pointsLabel(count: item.fencesCount)
        }
        
        // Hide speed test specific UI elements
        speedStackView.isHidden = true
        
    } else {
        // Regular speed test - existing logic
        configureSpeedTestCell(with: item)
    }
}
```

### Data Handling

Make sure to properly handle logic of other `TableViewDataSource/Delegate` methods and also `expandLoopSection` method

### Visual Specifications

- **Coverage Icon**: Use location/fence-style icon distinct from speed test icons
- **Typography**: Same as regular history items but different subtitle text
- **Spacing**: Maintain consistent row height with regular history items
- **Colors**: Use same color and fonts. Only difference will be icon and using less labels

## Technical Implementation Details

### Updated API Components

The following components have been updated to support coverage history:

1. **RMBTControlServer.swift:296-325**: Updated `/history` endpoint handler
   - Added `includeCoverageFences` parameter (defaults to `true`)
   - Maintains backward compatibility with existing method

2. **Sources/Requests/Requests.swift:48,58**: Updated request model
   - Added `includeCoverageFences: Bool?` property
   - Added JSON mapping for `"include_coverage_fences"`

3. **Sources/Models/HistoryItem.swift:70-72,104-105**: Updated response model
   - Added `isCoverageFences: Bool?` property
   - Added `fencesCount: Int?` property
   - Added JSON mappings for both fields

This implementation ensures coverage measurements are seamlessly integrated into the existing history view while being clearly identifiable as a different type of measurement.


# History Detail Network Coverage Implementation guide

## Overview
The History Detail Screen displays a read-only view of coverage measurement results, showing all measured fences (points) on a map along with test metadata and detailed information.

This view will be displayed when selectiong "Network Coverage" row of `RMBTHistoryIndexViewController`.   

## Implementation Approach

### Core Components Required
1. **Map View**: Display all fences from the measurement
2. **Coverage Result View**: Reuse existing `CoverageResultView` in read-only mode  
3. **Detail Information**: Show metadata and test details

### API Data Source

The detail screen should primarily use the `/RMBTStatisticServer/opentests/<test_UUID>` endpoint to retrieve fence data:

- **Endpoint**: `https://dev2.netztest.at/RMBTStatisticServer/opentests/Occ606684-c282-4e76-ab22-7c75831b065c`
- **Response contains**: The `fences` array with all measurement points including:
  - `fence_id`: Unique identifier for each fence
  - `technology_id` & `technology`: Network technology (e.g., "5G/NRNSA")
  - `longitude` & `latitude`: GPS coordinates
  - `offset_ms`: Time offset from measurement start
  - `duration_ms`: Duration of measurement at this point
  - `radius`: Accuracy radius of the measurement

### Implementation Steps

#### 1. Create Read-Only Coverage ViewModel

- Transform response data of `/RMBTStatisticServer/opentests/<test_UUID>` API into `[Fence]`
- Use `NetworkCoverageFactory.makeReadOnlyCoverageViewModel` method to create read-only `NetworkCoverageViewModel`

#### 2. Configure Map Display
- **Initial Focus**: Show all fences on screen (not current location)
- **Zoom Level**: Automatically fit all test points in view
- **User Location**: Do not display current location indicator
- **Interaction**: Allow pan and zoom but no new measurements

#### 3. Display Configuration
```swift
struct CoverageHistoryDetailView: View {
    let historyItem: HistoryItem
    @State private var coverageViewModel: NetworkCoverageViewModel?
    
    var body: some View {
        VStack {
            // Header with test metadata
            CoverageTestInfoHeader(
                dateTime: historyItem.timeString,
                fenceCount: historyItem.fencesCount,
                technologies: extractedTechnologies
            )
            
            // Coverage map view (read-only)
            if let coverageViewModel {
                CoverageResultView()
                    .environment(coverageViewModel)
            }
            
            // Additional details section
            CoverageTestDetailsView(testDetails: testDetails)
        }
        .onAppear {
            loadCoverageData()
        }
    }
}
```

#### 4. Data Loading Implementation
- Use existing `RMBTControlServer.getHistoryOpenDataResult` method to get data response.
- We might need to add additional fields for `fences` into `RMBTOpenDataResponse`.

#### 5. Metadata Display
Show test information from the API response:
- **Date/Time**: From history item `time_string`
- **Fence Count**: Total number of measurement points
- **Technologies**: List of network technologies used (extracted from fences)
- **Test Duration**: Calculated from fence timestamps
- **Additional Details**: Available via "More details" expandable section

#### 6. More Details Section
Implement expandable details similar to regular speed test details:
- Platform information (iOS, model, version)
- Network information (operator, IP details)
- Test metadata (test UUID, measurement type)
- Use key-value table format consistent with existing detail screens

### Technical Notes

#### Error Handling
- Handle cases where fence data is not available
- Display appropriate error messages for failed API calls
- Graceful degradation when partial data is available

#### Performance Considerations  
- Cache coverage data to avoid repeated API calls
- Implement loading states during data fetching
- Consider pagination for tests with many fences (though unlikely given measurement constraints)

#### Testing
- Test with various fence counts (single point, multiple points)
- Verify map displays correctly for different geographic spreads
- Test error scenarios (network failure, invalid test UUID)

This implementation ensures the History Detail Screen provides a comprehensive view of coverage measurements while reusing existing UI components and maintaining consistency with the app's architecture.
