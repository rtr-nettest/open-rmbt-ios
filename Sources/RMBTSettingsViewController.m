/*
 * Copyright 2013 appscape gmbh
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

#import "RMBTSettingsViewController.h"
#import "UIView+RMBTSubviews.h"
#import "RMBT-Swift.h"
#import <MessageUI/MFMailComposeViewController.h>

typedef NS_ENUM(NSInteger, RMBTSettingsSection) {
    RMBTSettingsSectionGeneral = 0,
    RMBTSettingsSectionAdvanced,
    RMBTSettingsSectionContacts,
    RMBTSettingsSectionInfo,
    RMBTSettingsSectionSupport,
    RMBTSettingsSectionDebug,
    RMBTSettingsSectionDebugCustomControlServer,
    RMBTSettingsSectionDebugLogging
};

@interface RMBTSettingsViewController()<MFMailComposeViewControllerDelegate> {
    NSString* _uuid;
}

@property (weak, nonatomic) IBOutlet UILabel *uuidLabel;
@property (weak, nonatomic) IBOutlet UILabel *testCounterLabel;
@property (weak, nonatomic) IBOutlet UILabel *buildDetailsLabel;
@property (weak, nonatomic) IBOutlet UILabel *developerNameLabel;

@property (strong, nonatomic) NSMutableArray *advancedSettings;
@property (weak, nonatomic) IBOutlet UISwitch *locationSwitcher;

@end

@implementation RMBTSettingsViewController

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    [self prepareAdvancedSettings];
    self.title = NSLocalizedString(@"preferences_general_settings", @"");
    self.navigationItem.leftBarButtonItem = self.closeBarButtonItem;
    
    self.developerNameLabel.text = RMBT_DEVELOPER_NAME;
    self.buildDetailsLabel.lineBreakMode = NSLineBreakByCharWrapping;
    self.buildDetailsLabel.text = [NSString stringWithFormat:@"%@(%@) %@\n(%@)",
                                   [[NSBundle mainBundle] infoDictionary]
                                    [@"CFBundleShortVersionString"],
                                   [[NSBundle mainBundle] infoDictionary]
                                    [@"CFBundleVersion"],
                                   RMBTBuildInfoString(),
                                   RMBTBuildDateString()];

    self.uuidLabel.lineBreakMode = NSLineBreakByCharWrapping;
    self.uuidLabel.numberOfLines = 0;
    
    [self updateLocationState: self];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(updateLocationState:) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    
    UITapGestureRecognizer *tapGestureRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(tapHandler:)];
    tapGestureRecognizer.numberOfTapsRequired = 10;
    [self.buildDetailsLabel addGestureRecognizer:tapGestureRecognizer];
    
    RMBTSettings *settings = [RMBTSettings sharedSettings];

    [self bindSwitch:self.forceIPv4Switch
   toSettingsKeyPath:@keypath(settings, forceIPv4)
            onToggle:^(BOOL value) {
                if (value && settings.debugUnlocked && self.debugForceIPv6Switch.on) {
                    settings.debugForceIPv6 = NO;
                    [self.debugForceIPv6Switch setOn:NO animated:YES];
                }
            }];

    [self bindSwitch:self.skipQoSSwitch
   toSettingsKeyPath:@keypath(settings, skipQoS)
            onToggle:nil];

    [self bindSwitch:self.expertModeSwitch
   toSettingsKeyPath:@keypath(settings, expertMode)
            onToggle:^(BOOL value) {
        [self prepareAdvancedSettings];
        [self.tableView reloadData];
    }];

    [self bindSwitch:self.loopModeSwitch
   toSettingsKeyPath:@keypath(settings, loopMode)
            onToggle:^(BOOL value) {
                if (value) {
                    // forget value in case user terminates the app while in the modal dialog
                    settings.loopMode = NO;
                    [self prepareAdvancedSettings];
                    [self performSegueWithIdentifier:@"show_loop_mode_confirmation" sender:self];
                } else {
                    [self prepareAdvancedSettings];
                    [self refreshSection:RMBTSettingsSectionAdvanced];
                }
    }];

    [self bindTextField:self.loopModeWaitTextField
      toSettingsKeyPath:@keypath(settings, loopModeEveryMinutes)
                numeric:YES
                    min:settings.debugUnlocked ? 1 : RMBT_TEST_LOOPMODE_MIN_DELAY_MINS
                    max:RMBT_TEST_LOOPMODE_MAX_DELAY_MINS
    ];

    [self bindTextField:self.loopModeDistanceTextField
      toSettingsKeyPath:@keypath(settings, loopModeEveryMeters)
                numeric:YES
                    min:settings.debugUnlocked ? 1 : RMBT_TEST_LOOPMODE_MIN_MOVEMENT_M
                    max:RMBT_TEST_LOOPMODE_MAX_MOVEMENT_M
    ];

    [self bindSwitch:self.debugForceIPv6Switch
   toSettingsKeyPath:@keypath(settings, debugForceIPv6) onToggle:^(BOOL value) {
       if (value && self.forceIPv4Switch.on) {
           settings.forceIPv4 = NO;
           [self.forceIPv4Switch setOn:NO animated:YES];
       }
   }];

    [self bindSwitch:self.debugControlServerCustomizationEnabledSwitch
   toSettingsKeyPath:@keypath(settings, debugControlServerCustomizationEnabled)
            onToggle:^(BOOL value) {
                [self refreshSection:RMBTSettingsSectionDebugCustomControlServer];
    }];

    [self bindTextField:self.debugControlServerHostnameTextField
      toSettingsKeyPath:@keypath(settings, debugControlServerHostname)
                numeric:NO];

    [self bindTextField:self.debugControlServerPortTextField
      toSettingsKeyPath:@keypath(settings, debugControlServerPort)
                numeric:YES];

    [self bindSwitch:self.debugControlServerUseSSLSwitch
   toSettingsKeyPath:@keypath(settings, debugControlServerUseSSL)
            onToggle:nil];

    [self bindSwitch:self.debugLoggingEnabledSwitch
   toSettingsKeyPath:@keypath(settings, debugLoggingEnabled)
            onToggle:^(BOOL value) {
                [self refreshSection:RMBTSettingsSectionDebugLogging];
    }];

    [self bindTextField:self.debugLoggingHostnameTextField
      toSettingsKeyPath:@keypath(settings, debugLoggingHostname)
                numeric:NO];

    [self bindTextField:self.debugLoggingPortTextField
      toSettingsKeyPath:@keypath(settings, debugLoggingPort)
                numeric:YES];
}

- (void)updateLocationState:(id)sender {
    [self.locationSwitcher setOn:[RMBTLocationTracker isAuthorized] animated:NO];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    // Refresh test counter and uuid labels:
    self.testCounterLabel.text = [NSString stringWithFormat:@"%lu",(unsigned long)[RMBTSettings sharedSettings].testCounter];

    _uuid = [RMBTControlServer sharedControlServer].uuid;
    if (_uuid) {
        self.uuidLabel.text = [NSString stringWithFormat:@"U%@",_uuid];
    }
}
- (void)viewWillDisappear:(BOOL)animated {
    [self.delegate settingsDidChangedIn:self];
    [[RMBTControlServer sharedControlServer] updateWithCurrentSettingsWithSuccess:^{
        
    } error:^(NSError * error) {
        
    }];
    [super viewWillDisappear:animated];
}

- (void)prepareAdvancedSettings {
    self.advancedSettings = [NSMutableArray array];
    [self.advancedSettings addObject:[NSIndexPath indexPathForRow:0 inSection:RMBTSettingsSectionAdvanced]];
    if ([RMBTSettings sharedSettings].loopMode) {
        [self.advancedSettings addObject:[NSIndexPath indexPathForRow:1 inSection:RMBTSettingsSectionAdvanced]];
        [self.advancedSettings addObject:[NSIndexPath indexPathForRow:2 inSection:RMBTSettingsSectionAdvanced]];
    }
    [self.advancedSettings addObject:[NSIndexPath indexPathForRow:3 inSection:RMBTSettingsSectionAdvanced]];
    if ([RMBTSettings sharedSettings].expertMode) {
        [self.advancedSettings addObject:[NSIndexPath indexPathForRow:4 inSection:RMBTSettingsSectionAdvanced]];
    }
}
#pragma mark - Two-way binding helpers

- (void)bindSwitch:(UISwitch*)aSwitch toSettingsKeyPath:(NSString*)keyPath onToggle:(void(^)(BOOL value))onToggle {
    aSwitch.on = [[[RMBTSettings sharedSettings] valueForKey:keyPath] boolValue];
    [aSwitch bk_addEventHandler:^(UISwitch *sender) {
        [[RMBTSettings sharedSettings] setValue:[NSNumber numberWithBool:sender.on] forKey:keyPath];
        if (onToggle) onToggle(sender.on);
    } forControlEvents:UIControlEventValueChanged];
}

- (void)bindTextField:(UITextField*)aTextField toSettingsKeyPath:(NSString*)keyPath numeric:(BOOL)numeric {
    [self bindTextField:aTextField toSettingsKeyPath:keyPath numeric:numeric min:NSIntegerMin max:NSIntegerMax];
}

- (void)bindTextField:(UITextField*)aTextField toSettingsKeyPath:(NSString*)keyPath numeric:(BOOL)numeric min:(NSInteger)min max:(NSInteger)max {
    id value = [[RMBTSettings sharedSettings] valueForKey:keyPath];
    NSString *stringValue = numeric ? [value stringValue] : value;
    if (numeric && [stringValue isEqualToString:@"0"]) stringValue = nil;
    aTextField.text = stringValue;

    [aTextField bk_addEventHandler:^(UITextField *sender) {
        NSInteger value = [sender.text integerValue];
        if (numeric && (value < min)) {
            sender.text = [@(min) stringValue];
        } else if (numeric && value > max) {
            sender.text = [@(max) stringValue];
        }
        id newValue = numeric ? [NSNumber numberWithInteger:[sender.text integerValue]] : sender.text;
        [[RMBTSettings sharedSettings] setValue:newValue forKey:keyPath];
    } forControlEvents:UIControlEventEditingDidEnd];
}

#pragma mark - Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    NSInteger lastSectionIndex = [RMBTSettings sharedSettings].debugUnlocked ? RMBTSettingsSectionDebugLogging : RMBTSettingsSectionSupport;
    return lastSectionIndex + 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RMBTSettingsSectionAdvanced) {
        NSIndexPath *itemIndexPath = self.advancedSettings[indexPath.row];
        return [super tableView:tableView cellForRowAtIndexPath:itemIndexPath];
    } else {
        return [super tableView:tableView cellForRowAtIndexPath:indexPath];
    }
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (section == RMBTSettingsSectionAdvanced) {
        return self.advancedSettings.count;
    } else if (section == RMBTSettingsSectionAdvanced && ![RMBTSettings sharedSettings].loopMode)  {
        return 1; // hide customization
    } else if (section == RMBTSettingsSectionDebugCustomControlServer && ![RMBTSettings sharedSettings].debugControlServerCustomizationEnabled) {
        return 1; // hide customization
    } else if (section == RMBTSettingsSectionDebugLogging && ![RMBTSettings sharedSettings].debugLoggingEnabled) {
        return 1; // hide customization
    } else {
        return [super tableView:tableView numberOfRowsInSection:section];
    }
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    CGFloat height = [self tableView:tableView heightForHeaderInSection:section];
    UIView *view = [[UIView alloc] initWithFrame:CGRectMake(0, 0, tableView.bounds.size.width, height)];
    view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    view.backgroundColor = UIColor.clearColor;
    
    UILabel *label = [[RMBTTitleSectionLabel alloc] initWithText:title];
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    label.frame = CGRectMake(20, 0, view.bounds.size.width - 40, height);
    [view addSubview:label];
    
    return view;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 48;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case RMBTSettingsSectionGeneral:
            return NSLocalizedString(@"preferences_general_settings", @"");
        case RMBTSettingsSectionAdvanced:
            return NSLocalizedString(@"preferences_advanced_settings", @"");
        case RMBTSettingsSectionContacts:
            return NSLocalizedString(@"preferences_contact", @"");
        case RMBTSettingsSectionInfo:
            return NSLocalizedString(@"preferences_additional_Information", @"");
        case RMBTSettingsSectionSupport:
            return NSLocalizedString(@"preferences_about", @"");
        case RMBTSettingsSectionDebug:
            return NSLocalizedString(@"preferences_debug_options", @"");
        case RMBTSettingsSectionDebugCustomControlServer:
            return NSLocalizedString(@"preferences_developer_control_server", @"");
        case RMBTSettingsSectionDebugLogging:
            return NSLocalizedString(@"preferences_developer_logging", @"");
        default:
            break;
    }
    return [super tableView:tableView titleForHeaderInSection:section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RMBTSettingsSectionDebugLogging) {
        return NSLocalizedString(@"preferences_developer_logging_summary", @"");
    }
    return [super tableView:tableView titleForFooterInSection:section];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RMBTSettingsSectionGeneral) {
        switch (indexPath.row) {
            case 1:
                [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] options:@{} completionHandler:nil];
                break;
                
            default:
                break;
        }
    } else if (indexPath.section == RMBTSettingsSectionContacts) {
        switch (indexPath.row) {
            case 0:
                [self presentModalBrowserWithURLString:RMBT_PROJECT_URL];
                break;
            case 1: {
                if ([MFMailComposeViewController canSendMail]) {
                    MFMailComposeViewController *mailVC = [[MFMailComposeViewController alloc] init];
                    [mailVC setToRecipients:@[RMBT_PROJECT_EMAIL]];
                    mailVC.mailComposeDelegate = self;
                    [self presentViewController:mailVC animated:YES completion:^{}];
                }
                break;
            }
            case 2:
                [self presentModalBrowserWithURLString:RMBT_PRIVACY_TOS_URL];
                break;
            default:
                NSAssert(false, @"Invalid row");
        }
    } else if (indexPath.section == RMBTSettingsSectionSupport) {
        switch (indexPath.row) {
            case 0:
                [self presentModalBrowserWithURLString:RMBT_DEVELOPER_URL];
                break;
            case 1:
                [self presentModalBrowserWithURLString:RMBT_REPO_URL];
                break;
        }
    }
    
    UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
    [cell.contentView rmbt_enumerateSubviewsOfType:[UITextField class] usingBlock:^(UIView *f) {
        UITextField* tf = (UITextField*)f;
        if (!tf.isFirstResponder) {
            [tf becomeFirstResponder];
        }
    }];
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

#pragma mark - Tableview actions (copying UUID)

// Show "Copy" action for cell showing client UUID
- (BOOL)tableView:(UITableView *)tableView shouldShowMenuForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == RMBTSettingsSectionInfo && indexPath.row == 0 && _uuid) {
        return YES;
    } else {
        return NO;
    }
}

// As client UUID is the only cell we can perform action for, we allow "copy" here
- (BOOL)tableView:(UITableView *)tableView canPerformAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    return (action == @selector(copy:));
}

// ..and we copy the UUID value to pastboard in case "copy" action is performed
- (void)tableView:(UITableView *)tableView performAction:(SEL)action forRowAtIndexPath:(NSIndexPath *)indexPath withSender:(id)sender {
    if (action == @selector(copy:)) {
        // Copy UUID to pasteboard
        [[UIPasteboard generalPasteboard] setString:_uuid];
    }
}

- (void)refreshSection:(RMBTSettingsSection)section {
    NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:section];
    [self.tableView beginUpdates];
    [self.tableView reloadSections:indexSet withRowAnimation: UITableViewRowAnimationAutomatic];
    [self.tableView reloadData];
    [self.tableView endUpdates];
}

#pragma mark - Textfield delegate

- (BOOL)textFieldShouldReturn:(UITextField *)textField {
    [textField resignFirstResponder];
    return YES;
}

#pragma mark - Loop mode confirmation

- (IBAction)declineLoopModeConfirmation:(UIStoryboardSegue*)segue {
    [self.loopModeSwitch setOn:NO];
    [segue.sourceViewController dismissViewControllerAnimated:YES completion:nil];
}

- (IBAction)acceptLoopModeConfirmation:(UIStoryboardSegue*)segue {
    [RMBTSettings sharedSettings].loopMode = YES;
    [self prepareAdvancedSettings];
    [self refreshSection:RMBTSettingsSectionAdvanced];
}

- (void)mailComposeController:(MFMailComposeViewController*)controller
          didFinishWithResult:(MFMailComposeResult)result
                        error:(NSError*)error {
    [self dismissViewControllerAnimated:YES completion:^{}];
}
@end
