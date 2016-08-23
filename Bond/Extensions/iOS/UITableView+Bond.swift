//
//  The MIT License (MIT)
//
//  Copyright (c) 2015 Srdan Rasic (@srdanrasic)
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.
//

import UIKit

@objc public protocol BNDTableViewProxyDataSource {
  @objc optional func tableView(tableView: UITableView, titleForHeaderInSection section: Int) -> String?
  @objc optional func tableView(tableView: UITableView, titleForFooterInSection section: Int) -> String?
  @objc optional func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: IndexPath) -> Bool
  @objc optional func tableView(tableView: UITableView, canMoveRowAtIndexPath indexPath: IndexPath) -> Bool
  @objc optional func sectionIndexTitlesForTableView(tableView: UITableView) -> [String]?
  @objc optional func tableView(tableView: UITableView, sectionForSectionIndexTitle title: String, atIndex index: Int) -> Int
  @objc optional func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: IndexPath)
  @objc optional func tableView(tableView: UITableView, moveRowAtIndexPath sourceIndexPath: IndexPath, toIndexPath destinationIndexPath: IndexPath)
  
  /// Override to specify reload or update
  @objc optional func shouldReloadInsteadOfUpdateTableView(tableView: UITableView) -> Bool
  
  /// Override to specify custom row animation when row is being inserted, deleted or updated
  @objc optional func tableView(tableView: UITableView, animationForRowAtIndexPaths indexPaths: [IndexPath]) -> UITableViewRowAnimation
  
  /// Override to specify custom row animation when section is being inserted, deleted or updated
  @objc optional func tableView(tableView: UITableView, animationForRowInSections sections: Set<Int>) -> UITableViewRowAnimation
}

class BNDTableViewDataSource<T>: NSObject, UITableViewDataSource {
  
  private let array: ObservableArray<ObservableArray<T>>
  private weak var tableView: UITableView!
  private let createCell: @escaping (IndexPath, ObservableArray<ObservableArray<T>>, UITableView) -> UITableViewCell
  private weak var proxyDataSource: BNDTableViewProxyDataSource?
  private let sectionObservingDisposeBag = DisposeBag()
  
  init(array: ObservableArray<ObservableArray<T>>, tableView: UITableView, proxyDataSource: BNDTableViewProxyDataSource?, createCell: @escaping (IndexPath, ObservableArray<ObservableArray<T>>, UITableView) -> UITableViewCell) {
    self.tableView = tableView
    self.createCell = createCell
    self.proxyDataSource = proxyDataSource
    self.array = array
    super.init()
    
    tableView.dataSource = self
    tableView.reloadData()
    setupPerSectionObservers()
    
    array.observeNew { [weak self] arrayEvent in
      guard let unwrappedSelf = self, let tableView = unwrappedSelf.tableView else { return }

      if let reload = unwrappedSelf.proxyDataSource?.shouldReloadInsteadOfUpdateTableView?(tableView: tableView) , reload {
        tableView.reloadData()
      } else {
        switch arrayEvent.operation {
        case .Batch(let operations):
          tableView.beginUpdates()
          for diff in changeSetsFromBatchOperations(operations: operations) {
            BNDTableViewDataSource.applySectionUnitChangeSet(changeSet: diff, tableView: tableView, dataSource: unwrappedSelf.proxyDataSource)
          }
          tableView.endUpdates()
        case .Reset:
          tableView.reloadData()
        default:
          BNDTableViewDataSource.applySectionUnitChangeSet(changeSet: arrayEvent.operation.changeSet(), tableView: tableView, dataSource: unwrappedSelf.proxyDataSource)
        }
      }
      
      unwrappedSelf.setupPerSectionObservers()
    }.disposeIn(bnd_bag)
  }
  
  private func setupPerSectionObservers() {
    sectionObservingDisposeBag.dispose()

    for (sectionIndex, sectionObservableArray) in array.enumerated() {
      sectionObservableArray.observeNew {
        [weak tableView, weak self] arrayEvent in
        guard let tableView = tableView else { return }
        if let reload = self?.proxyDataSource?.shouldReloadInsteadOfUpdateTableView?(tableView: tableView) , reload { tableView.reloadData(); return }
        
        switch arrayEvent.operation {
        case .Batch(let operations):
          tableView.beginUpdates()
          for diff in changeSetsFromBatchOperations(operations: operations) {
            BNDTableViewDataSource.applyRowUnitChangeSet(changeSet: diff, tableView: tableView, sectionIndex: sectionIndex, dataSource: self?.proxyDataSource)
          }
          tableView.endUpdates()
        case .Reset:
          let indices = Set([sectionIndex])
          tableView.reloadSections(NSIndexSet(index: sectionIndex) as IndexSet, with: self?.proxyDataSource?.tableView?(tableView: tableView, animationForRowInSections: indices) ?? .automatic)
        default:
          BNDTableViewDataSource.applyRowUnitChangeSet(changeSet: arrayEvent.operation.changeSet(), tableView: tableView, sectionIndex: sectionIndex, dataSource: self?.proxyDataSource)
        }
      }.disposeIn(sectionObservingDisposeBag)
    }
  }
  
  private class func applySectionUnitChangeSet(changeSet: ObservableArrayEventChangeSet, tableView: UITableView, dataSource: BNDTableViewProxyDataSource?) {
    switch changeSet {
    case .Inserts(let indices):
      tableView.insertSections(NSIndexSet(set: indices) as IndexSet, with: dataSource?.tableView?(tableView: tableView, animationForRowInSections: indices) ?? .automatic)
    case .Updates(let indices):
      tableView.reloadSections(NSIndexSet(set: indices) as IndexSet, with: dataSource?.tableView?(tableView: tableView, animationForRowInSections: indices) ?? .automatic)
    case .Deletes(let indices):
      tableView.deleteSections(NSIndexSet(set: indices) as IndexSet, with: dataSource?.tableView?(tableView: tableView, animationForRowInSections: indices) ?? .automatic)
    }
  }
  
  private class func applyRowUnitChangeSet(changeSet: ObservableArrayEventChangeSet, tableView: UITableView, sectionIndex: Int, dataSource: BNDTableViewProxyDataSource?) {
    switch changeSet {
    case .Inserts(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      tableView.insertRows(at: indexPaths, with: dataSource?.tableView?(tableView: tableView, animationForRowAtIndexPaths: indexPaths) ?? .automatic)
    case .Updates(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      tableView.reloadRows(at: indexPaths, with: dataSource?.tableView?(tableView: tableView, animationForRowAtIndexPaths: indexPaths) ?? .automatic)
    case .Deletes(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      tableView.deleteRows(at: indexPaths, with: dataSource?.tableView?(tableView: tableView, animationForRowAtIndexPaths: indexPaths) ?? .automatic)
    }
  }
  
  /// MARK - UITableViewDataSource
  
  @objc(numberOfSectionsInTableView:) func numberOfSections(in tableView: UITableView) -> Int {
    return array.count
  }
  
  @objc func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return array[section].count
  }
  
  @objc func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
    return createCell(indexPath, array, tableView)
  }
  
  @objc func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
    //return proxyDataSource?.tableView?(tableView, titleForHeaderInSection: section)
    return proxyDataSource?.tableView?(tableView: tableView, titleForHeaderInSection: section)
  }
  
  @objc func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
      return proxyDataSource?.tableView?(tableView: tableView, titleForFooterInSection: section)
  }
  
  @objc func tableView(_ tableView: UITableView, canEditRowAt indexPath: IndexPath) -> Bool {
    return proxyDataSource?.tableView?(tableView: tableView, canEditRowAtIndexPath: indexPath) ?? false
  }
  
  @objc func tableView(_ tableView: UITableView, canMoveRowAt indexPath: IndexPath) -> Bool {
    return proxyDataSource?.tableView?(tableView: tableView, canMoveRowAtIndexPath: indexPath) ?? false
  }
  
  @objc func sectionIndexTitles(for tableView: UITableView) -> [String]? {
    return proxyDataSource?.sectionIndexTitlesForTableView?(tableView: tableView)
  }
  
  @objc func tableView(_ tableView: UITableView, sectionForSectionIndexTitle title: String, at index: Int) -> Int {
    if let section = proxyDataSource?.tableView?(tableView: tableView, sectionForSectionIndexTitle: title, atIndex: index) {
      return section
    } else {
      fatalError("Dear Sir/Madam, your table view has asked for section for section index title \(title). Please provide a proxy data source object in bindTo() method that implements `tableView(tableView:sectionForSectionIndexTitle:atIndex:)` method!")
    }
  }
  
  @objc func tableView(_ tableView: UITableView, commit editingStyle: UITableViewCellEditingStyle, forRowAt indexPath: IndexPath) {
    proxyDataSource?.tableView?(tableView: tableView, commitEditingStyle: editingStyle, forRowAtIndexPath: indexPath)
  }
  
  @objc func tableView(_ tableView: UITableView, moveRowAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    proxyDataSource?.tableView?(tableView: tableView, moveRowAtIndexPath: sourceIndexPath, toIndexPath: destinationIndexPath)
  }
}

extension UITableView {
  fileprivate struct AssociatedKeys {
    static var BondDataSourceKey = "bnd_BondDataSourceKey"
  }
}

public extension EventProducerType where
  EventType: ObservableArrayEventType,
  EventType.ObservableArrayEventSequenceType.Iterator.Element: EventProducerType,
  EventType.ObservableArrayEventSequenceType.Iterator.Element.EventType: ObservableArrayEventType {
  
  private typealias ElementType = EventType.ObservableArrayEventSequenceType.Iterator.Element.EventType.ObservableArrayEventSequenceType.Iterator.Element
  
  public func bindTo(tableView: UITableView, proxyDataSource: BNDTableViewProxyDataSource? = nil, createCell: @escaping (IndexPath, ObservableArray<ObservableArray<ElementType>>, UITableView) -> UITableViewCell) -> DisposableType {
    
    let array: ObservableArray<ObservableArray<ElementType>>
    if let downcastedObservableArray = self as? ObservableArray<ObservableArray<ElementType>> {
      array = downcastedObservableArray
    } else {
      array = self.map { $0.crystallize() }.crystallize()
    }
    
    let dataSource = BNDTableViewDataSource(array: array, tableView: tableView, proxyDataSource: proxyDataSource, createCell: createCell)
    objc_setAssociatedObject(tableView, &UITableView.AssociatedKeys.BondDataSourceKey, dataSource, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    
    return BlockDisposable { [weak tableView] in
      if let tableView = tableView {
        objc_setAssociatedObject(tableView, &UITableView.AssociatedKeys.BondDataSourceKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
    }
  }
}
