//
//  SettingsNavigationViewController.swift
//  LoopKitUI
//
//  Created by Pete Schwamb on 1/29/19.
//  Copyright © 2019 LoopKit Authors. All rights reserved.
//

import UIKit

open class SettingsNavigationViewController: UINavigationController, CompletionNotifying {

    open weak var completionDelegate: CompletionDelegate?

    open func notifyComplete() {
        completionDelegate?.completionNotifyingDidComplete(self)
    }

}
