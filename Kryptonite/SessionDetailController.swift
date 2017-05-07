//
//  SessionDetailController.swift
//  Kryptonite
//
//  Created by Alex Grinman on 9/13/16.
//  Copyright © 2016 KryptCo, Inc. All rights reserved.
//

import UIKit

class SessionDetailController: KRBaseTableController, UITextFieldDelegate {

    @IBOutlet var deviceNameField:UITextField!
    @IBOutlet var lastAccessLabel:UILabel!

    @IBOutlet var revokeButton:UIButton!

    @IBOutlet var headerView:UIView!

    @IBOutlet weak var approvalSegmentedControl:UISegmentedControl!
    @IBOutlet weak var hideApprovedNotificationsToggle:UISwitch!

    enum ApprovalControl:Int {
        case on = 0
        case timed = 1
        case off = 2
    }
    var logs:[SignatureLog] = []
    var session:Session?
    
    var timer:Timer?
    

    override func viewDidLoad() {
        super.viewDidLoad()
        self.title = "Details"
        
        tableView.rowHeight = UITableViewAutomaticDimension
        tableView.estimatedRowHeight = 40
        
        
        if let font = UIFont(name: "AvenirNext-Bold", size: 12) {
            approvalSegmentedControl.setTitleTextAttributes([
                NSFontAttributeName: font,
            ], for: UIControlState.normal)
        }

        
        if let session = session {
            deviceNameField.text = session.pairing.displayName.uppercased()
            hideApprovedNotificationsToggle.isOn = Policy.shouldShowApprovedNotifications(for: session)
            
            logs = LogManager.shared.fetch(for: session.id)
            lastAccessLabel.text =  "Active " + (logs.first?.date.timeAgo() ?? session.created.timeAgo())
            
            updateApprovalControl(session: session)

        }
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        NotificationCenter.default.addObserver(self, selector: #selector(SessionDetailController.newLogLine), name: NSNotification.Name(rawValue: "new_log"), object: nil)

        headerView.layer.shadowColor = UIColor.black.cgColor
        headerView.layer.shadowOffset = CGSize(width: 0, height: 0)
        headerView.layer.shadowOpacity = 0.175
        headerView.layer.shadowRadius = 3
        headerView.layer.masksToBounds = false
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        
        NotificationCenter.default.removeObserver(self, name: NSNotification.Name(rawValue: "new_log"), object: nil)
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    dynamic func newLogLine() {
        log("new log")
        guard let session = session else {
            return
        }
        
        dispatchAsync {
            self.logs = LogManager.shared.fetch(for: session.id).sorted(by: { $0.date > $1.date })
            
            dispatchMain {                
                self.lastAccessLabel.text =  "Active as of " + (self.logs.first?.date.timeAgo() ?? session.created.timeAgo())
                self.tableView.reloadData()
            }
        }
        
        dispatchMain {
           self.updateApprovalControl(session: session)
        }
    }

    @IBAction func userApprovalSettingChanged(sender:UISegmentedControl) {
        guard let session = session, let approvalControlType = ApprovalControl(rawValue: sender.selectedSegmentIndex) else {
            log("unknown session or approval segmented control index", .error)
            return
        }
        
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }

        switch approvalControlType {
        case .on:
            Analytics.postEvent(category: "manual approval", action: String(true))
            Policy.set(needsUserApproval: true, for: session)

        case .timed:
            Analytics.postEvent(category: "manual approval", action: "time", value: UInt(Policy.Interval.threeHours.rawValue))
            Policy.allow(session: session, for: Policy.Interval.threeHours)

        case .off:
            Analytics.postEvent(category: "manual approval", action: String(false))
            Policy.set(needsUserApproval: false, for: session)
        }
        
        approvalSegmentedControl.setTitle("Don't ask for 3hrs", forSegmentAt: ApprovalControl.timed.rawValue)
    }


    //MARK: Revoke
    @IBAction func revokeTapped() {
        
        if #available(iOS 10.0, *) {
            UIImpactFeedbackGenerator(style: UIImpactFeedbackStyle.heavy).impactOccurred()
        }

        if let session = session {
            Analytics.postEvent(category: "device", action: "unpair", label: "detail")
            SessionManager.shared.remove(session: session)
            TransportControl.shared.remove(session: session)
        }
        let _ = self.navigationController?.popViewController(animated: true)
    }
    
    func updateApprovalControl(session:Session) {
        if Policy.needsUserApproval(for: session)  {
            approvalSegmentedControl.selectedSegmentIndex = ApprovalControl.on.rawValue
        }
        else if let remaining = Policy.approvalTimeRemaining(for: session) {
            approvalSegmentedControl.selectedSegmentIndex = 1
            approvalSegmentedControl.setTitle("Don't ask for \(remaining)", forSegmentAt: ApprovalControl.timed.rawValue)
        }
        else {
            approvalSegmentedControl.selectedSegmentIndex = ApprovalControl.off.rawValue
        }
    }
    
    //MARK: Edit Device Session Name
    
    func textFieldDidBeginEditing(_ textField: UITextField) {
        guard let session = session else {
            return
        }

        textField.text = session.pairing.displayName
    }
    func textField(_ textField: UITextField, shouldChangeCharactersIn range: NSRange, replacementString string: String) -> Bool {
        return true
    }
    
    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        
        guard let name = textField.text, let session = session else {
            return false
        }
        
        if name.isEmpty {
            return false
        } else {
            SessionManager.shared.changeSessionPairingName(of: session.id, to: name)
            self.session?.pairing.name = name
            deviceNameField.text = name.uppercased()
        }
        
        textField.resignFirstResponder()
        return true
    }


    //MARK: Hide Approved Notifications Toggle
    @IBAction func hideApprovedNotificationsToggled(sender:UISwitch) {
        guard let session = session else {
            return
        }
        
        Policy.set(shouldShowApprovedNotifications: sender.isOn, for: session)
        
        Analytics.postEvent(category: "show auto-approved notifications", action: "\(sender.isOn)")
    }

    
    
    // MARK: - Table view data source

    override func numberOfSections(in tableView: UITableView) -> Int {
        return 1
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return logs.count
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        return "Access Logs"
    }
    
    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "LogCell") as! LogCell
        cell.set(log: logs[indexPath.row])
        return cell
    }
 
//    override func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
//        return 80.0
//        
//    }
    /*
    // Override to support conditional editing of the table view.
    override func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the specified item to be editable.
        return true
    }
    */

    /*
    // Override to support editing the table view.
    override func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
        if editingStyle == .delete {
            // Delete the row from the data source
            tableView.deleteRows(at: [indexPath], with: .fade)
        } else if editingStyle == .insert {
            // Create a new instance of the appropriate class, insert it into the array, and add a new row to the table view
        }    
    }
    */

    /*
    // Override to support rearranging the table view.
    override func tableView(_ tableView: UITableView, moveRowAt fromIndexPath: IndexPath, to: IndexPath) {

    }
    */

    /*
    // Override to support conditional rearranging of the table view.
    override func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
        // Return false if you do not want the item to be re-orderable.
        return true
    }
    */

    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepare(for segue: UIStoryboardSegue, sender: Any?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
