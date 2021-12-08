/*
 * Copyright 2017 appscape gmbh
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
 *
 */

#import "RMBTLoopDetailsCell.h"
#import "RMBT-Swift.h"

@implementation RMBTLoopDetailsCell

- (void)awakeFromNib {
    [super awakeFromNib];

    self.fieldLabel.text = nil;
    self.detailsLabel.text = nil;
}

- (void)setCompact:(BOOL)compact {
    [UIFont robotoWithSize:compact ? 15.0f : 17.0f weight:UIFontWeightRegular];
    self.fieldLabel.font = [UIFont robotoWithSize:compact ? 15.0f : 17.0f weight:UIFontWeightRegular];
    self.detailsLabel.font = [UIFont robotoWithSize:compact ? 15.0f : 17.0f weight:UIFontWeightRegular];
}
@end
