platform :ios, '17.0'

# ignore all warnings from all pods
inhibit_all_warnings!

use_frameworks!

target 'RMBT' do
  pod 'Alamofire'
  pod 'AlamofireObjectMapper'
  pod 'XCGLogger'
  pod 'CocoaAsyncSocket'
  
  pod 'ReachabilitySwift'
  
  pod 'BlocksKit/UIKit', :git => 'https://github.com/sglushchenko/BlocksKit', :branch => 'without_UIWebView'
  pod 'BlocksKit/MessageUI', :git => 'https://github.com/sglushchenko/BlocksKit', :branch => 'without_UIWebView'
  
  pod 'libextobjc/EXTKeyPathCoding'
  pod 'TUSafariActivity'
  pod 'KeychainAccess'

  
#  if File.exist?(File.expand_path('../Vendor/CocoaAsyncSocket', __FILE__))
#    pod 'CocoaAsyncSocket', :path => 'Vendor/CocoaAsyncSocket'
#  else
#    pod 'CocoaAsyncSocket', :git => 'https://github.com/appscape/CocoaAsyncSocket.git',
#                            :commit => '350ac5f09002ac92a333175cb87ab8b59ebd0571'
#  end

  pod 'BCGenieEffect'
  pod 'MaterialComponents/Tabs+TabBarView'
  
  post_install do |installer|
    installer.generated_projects.each do |project|
      project.targets.each do |target|
        target.build_configurations.each do |config|
           config.build_settings['IPHONEOS_DEPLOYMENT_TARGET'] = '17.0'
        end
      end
    end
  end
end
