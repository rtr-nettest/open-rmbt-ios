//
//  RMBTPopupViewController.swift
//  RMBT
//
//  Created by Sergey Glushchenko on 13.08.2021.
//  Copyright © 2021 appscape gmbh. All rights reserved.
//

import UIKit

struct RMBTPopupInfo {
    struct Value {
        let title: String?
        let value: String?
    }
    
    enum Style {
        case line
        case list
    }
    
    let icon: UIImage?
    let style: Style
    var tintColor: UIColor?
    var values: [Value] = []
    
    init(with icon: UIImage?, tintColor: UIColor?, style: Style = .list, values: [Value]) {
        self.icon = icon
        self.tintColor = tintColor
        self.values = values
        self.style = style
    }
}

enum PopupType {
    case location
    case ipv4
    case ipv6
}

class RMBTPopupViewController: UIViewController {

    @IBOutlet weak var ipNotAvailableLabel: UILabel?
    @IBOutlet private weak var heightConstraint: NSLayoutConstraint!
    @IBOutlet private weak var topConstraint: NSLayoutConstraint!
    
    @IBOutlet private weak var infoTypeImageView: UIImageView?
    @IBOutlet private weak var contentView: UIView!
    @IBOutlet weak var collectionView: UICollectionView!
    
    private var timer: Timer?
    
    public var popupType: PopupType = .ipv4
    
    public var info: RMBTPopupInfo? {
        didSet {
            if self.isViewLoaded {
                updateUI()
            }
        }
    }
    
    public var onTickHandler: (_ vc: RMBTPopupViewController) -> Void = { _ in }
    
    static func present(with info: RMBTPopupInfo, in vc: UIViewController, tickHandler: @escaping (_ vc: RMBTPopupViewController) -> Void = {_ in }) -> RMBTPopupViewController? {
        let navController = UIStoryboard(name: "MainStoryboard", bundle: nil).instantiateViewController(withIdentifier: "RMBTPopupNavigationController") as! UINavigationController
        guard let popupViewController = navController.topViewController as? RMBTPopupViewController else { return nil }
        popupViewController.info = info
        popupViewController.onTickHandler = tickHandler
        navController.modalPresentationStyle = .overFullScreen
        navController.modalTransitionStyle = .crossDissolve
        vc.present(navController, animated: false, completion: nil)
        return popupViewController
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        self.ipNotAvailableLabel?.text = NSLocalizedString("text_ip_address_not_available", comment: "")
        
        self.collectionView.register(UINib(nibName: RMBTPopupCollectionView.ID, bundle: nil), forCellWithReuseIdentifier: RMBTPopupCollectionView.ID)
        
        self.contentView.layer.shadowOffset = CGSize(width: 0, height: 16)
        self.contentView.layer.shadowRadius = 24
        self.contentView.layer.shadowOpacity = 0.2
        self.contentView.clipsToBounds = false
        
        self.view.layoutIfNeeded()
        self.updateUI()
        self.topConstraint.constant = -(self.contentView.bounds.height + self.view.safeAreaInsets.top + 50)
        self.view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(dismissHandler(_:))))
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            self.showAnimation()
        }
        
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true, block: { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                self.onTickHandler(self)
            }
        })
    }
    
    func contentHeight() -> CGFloat {
        if info?.style == .line {
            return CGFloat(53)
        } else {
            return CGFloat((self.info?.values.count ?? 0) * 53)
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        self.updateUI()
    }
    
    private func updateUI() {
        self.ipNotAvailableLabel?.isHidden = !(self.info?.values.count == 0)
        self.heightConstraint.constant = self.contentHeight()
        self.infoTypeImageView?.image = info?.icon
        self.infoTypeImageView?.image = self.infoTypeImageView?.image?.withRenderingMode(.alwaysTemplate)
        self.infoTypeImageView?.tintColor = self.info?.tintColor

        if self.info?.values.count == 0 {
            infoTypeImageView?.isAccessibilityElement = true
            infoTypeImageView?.accessibilityLabel = ipNotAvailableLabel?.text
        }
        self.collectionView.reloadData()
    }
    
    private func showAnimation() {
        UIView.animate(withDuration: 0.3) {
            self.topConstraint.constant = 8
            self.view.layoutIfNeeded()
        }
    }
    
    private func hideAnimation(complete: @escaping () -> Void) {
        UIView.animate(withDuration: 0.3, animations:{
            self.topConstraint.constant = -(self.contentView.bounds.height + self.view.safeAreaInsets.top + 10)
            self.view.layoutIfNeeded()
        }) { _ in
            complete()
        }
    }
    
    @objc private func dismissHandler(_ sender: Any) {
        self.view.isUserInteractionEnabled = false
        if self.timer?.isValid == true {
            self.timer?.invalidate()
            self.timer = nil
        }
        self.hideAnimation {
            self.dismiss(animated: false, completion: nil)
        }
    }
}

extension RMBTPopupViewController: UICollectionViewDelegate, UICollectionViewDataSource, UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if self.info?.style == .list {
            return CGSize(width: collectionView.bounds.width, height: 53)
        } else {
            return CGSize(width: collectionView.bounds.width / CGFloat(self.info?.values.count ?? 1), height: 53)
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let value = self.info?.values[indexPath.row]
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: RMBTPopupCollectionView.ID, for: indexPath) as! RMBTPopupCollectionView
        cell.value = value
        return cell
    }
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return info?.values.count ?? 0
    }
}
