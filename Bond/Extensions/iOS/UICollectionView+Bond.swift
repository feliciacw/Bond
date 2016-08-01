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

@objc public protocol BNDCollectionViewProxyDataSource {
  @objc optional func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath: NSIndexPath) -> UICollectionReusableView
  @objc optional func collectionView(collectionView: UICollectionView, canMoveItemAtIndexPath indexPath: NSIndexPath) -> Bool
  @objc optional func collectionView(collectionView: UICollectionView, moveItemAtIndexPath sourceIndexPath: NSIndexPath, toIndexPath destinationIndexPath: NSIndexPath)

  /// Override to specify reload or update
  @objc optional func shouldReloadInsteadOfUpdateCollectionView(collectionView: UICollectionView) -> Bool
}

private class BNDCollectionViewDataSource<T>: NSObject, UICollectionViewDataSource {
  
  private let array: ObservableArray<ObservableArray<T>>
  private weak var collectionView: UICollectionView!
  private let createCell: (NSIndexPath, ObservableArray<ObservableArray<T>>, UICollectionView) -> UICollectionViewCell
  private weak var proxyDataSource: BNDCollectionViewProxyDataSource?
  private let sectionObservingDisposeBag = DisposeBag()
  
  private init(array: ObservableArray<ObservableArray<T>>, collectionView: UICollectionView, proxyDataSource: BNDCollectionViewProxyDataSource?, createCell: (NSIndexPath, ObservableArray<ObservableArray<T>>, UICollectionView) -> UICollectionViewCell) {
    self.collectionView = collectionView
    self.createCell = createCell
    self.proxyDataSource = proxyDataSource
    self.array = array
    super.init()
    
    collectionView.dataSource = self
    collectionView.reloadData()
    setupPerSectionObservers()
    
    array.observeNew { [weak self] arrayEvent in
      guard let unwrappedSelf = self, let collectionView = unwrappedSelf.collectionView else { return }

      if let reload = unwrappedSelf.proxyDataSource?.shouldReloadInsteadOfUpdateCollectionView?(collectionView: collectionView) where reload {
        collectionView.reloadData()
      } else {
        switch arrayEvent.operation {
        case .Batch(let operations):
          collectionView.performBatchUpdates({
            for operation in changeSetsFromBatchOperations(operations: operations) {
              BNDCollectionViewDataSource.applySectionUnitChangeSet(changeSet: operation, collectionView: collectionView)
            }
            }, completion: nil)
        case .Reset:
          collectionView.reloadData()
        default:
          BNDCollectionViewDataSource.applySectionUnitChangeSet(changeSet: arrayEvent.operation.changeSet(), collectionView: collectionView)
        }
      }

      unwrappedSelf.setupPerSectionObservers()
    }.disposeIn(disposeBag: bnd_bag)
  }
  
  private func setupPerSectionObservers() {
    sectionObservingDisposeBag.dispose()
    
    for (sectionIndex, sectionObservableArray) in array.enumerated() {
      sectionObservableArray.observeNew { [weak collectionView, weak proxyDataSource] arrayEvent in
        guard let collectionView = collectionView else { return }
        if let reload = proxyDataSource?.shouldReloadInsteadOfUpdateCollectionView?(collectionView: collectionView) where reload { collectionView.reloadData(); return }

        switch arrayEvent.operation {
        case .Batch(let operations):
          collectionView.performBatchUpdates({
            for operation in changeSetsFromBatchOperations(operations: operations) {
              BNDCollectionViewDataSource.applyRowUnitChangeSet(changeSet: operation, collectionView: collectionView, sectionIndex: sectionIndex)
            }
          }, completion: nil)
        case .Reset:
          collectionView.reloadSections(NSIndexSet(index: sectionIndex) as IndexSet)
        default:
          BNDCollectionViewDataSource.applyRowUnitChangeSet(changeSet: arrayEvent.operation.changeSet(), collectionView: collectionView, sectionIndex: sectionIndex)
        }
      }.disposeIn(disposeBag: sectionObservingDisposeBag)
    }
  }
  
  private class func applySectionUnitChangeSet(changeSet: ObservableArrayEventChangeSet, collectionView: UICollectionView) {
    switch changeSet {
    case .Inserts(let indices):
      collectionView.insertSections(NSIndexSet(set: indices) as IndexSet)
    case .Updates(let indices):
      collectionView.reloadSections(NSIndexSet(set: indices) as IndexSet)
    case .Deletes(let indices):
      collectionView.deleteSections(NSIndexSet(set: indices) as IndexSet)
    }
  }
  
  private class func applyRowUnitChangeSet(changeSet: ObservableArrayEventChangeSet, collectionView: UICollectionView, sectionIndex: Int) {
    switch changeSet {
    case .Inserts(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      collectionView.insertItems(at: indexPaths)
    case .Updates(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      collectionView.reloadItems(at: indexPaths)
    case .Deletes(let indices):
      let indexPaths = indices.map { IndexPath(item: $0, section: sectionIndex) }
      collectionView.deleteItems(at: indexPaths)
    }
  }
  
  /// MARK - UICollectionViewDataSource
  
  @objc func numberOfSections(in collectionView: UICollectionView) -> Int {
    return array.count
  }
  
  @objc func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
    return array[section].count
  }
  
  @objc func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
    return createCell(indexPath, array, collectionView)
  }
  
  @objc func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
    if let view = proxyDataSource?.collectionView?(collectionView: collectionView, viewForSupplementaryElementOfKind: kind, atIndexPath: indexPath) {
      return view
    } else {
      fatalError("Dear Sir/Madam, your collection view has asked for a supplementary view of a \(kind) kind. Please provide a proxy data source object in bindTo() method that implements `collectionView(collectionView:viewForSupplementaryElementOfKind:atIndexPath)` method!")
    }
  }
  
  @objc func collectionView(_ collectionView: UICollectionView, canMoveItemAt indexPath: IndexPath) -> Bool {
    return proxyDataSource?.collectionView?(collectionView: collectionView, canMoveItemAtIndexPath: indexPath) ?? false
  }
  
  @objc func collectionView(_ collectionView: UICollectionView, moveItemAt sourceIndexPath: IndexPath, to destinationIndexPath: IndexPath) {
    proxyDataSource?.collectionView?(collectionView: collectionView, moveItemAtIndexPath: sourceIndexPath, toIndexPath: destinationIndexPath)
  }
}

extension UICollectionView {
  private struct AssociatedKeys {
    static var BondDataSourceKey = "bnd_BondDataSourceKey"
  }
}

public extension EventProducerType where
  EventType: ObservableArrayEventType,
  EventType.ObservableArrayEventSequenceType.Iterator.Element: EventProducerType,
  EventType.ObservableArrayEventSequenceType.Iterator.Element.EventType: ObservableArrayEventType {
  
  private typealias ElementType = EventType.ObservableArrayEventSequenceType.Iterator.Element.EventType.ObservableArrayEventSequenceType.Iterator.Element
  
  public func bindTo(collectionView: UICollectionView, proxyDataSource: BNDCollectionViewProxyDataSource? = nil, createCell: (NSIndexPath, ObservableArray<ObservableArray<ElementType>>, UICollectionView) -> UICollectionViewCell) -> DisposableType {
    
    let array: ObservableArray<ObservableArray<ElementType>>
    if let downcastedObservableArray = self as? ObservableArray<ObservableArray<ElementType>> {
      array = downcastedObservableArray
    } else {
      array = self.map { $0.crystallize() }.crystallize()
    }
    
    let dataSource = BNDCollectionViewDataSource(array: array, collectionView: collectionView, proxyDataSource: proxyDataSource, createCell: createCell)
    collectionView.dataSource = dataSource
    objc_setAssociatedObject(collectionView, &UICollectionView.AssociatedKeys.BondDataSourceKey, dataSource, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    
    return BlockDisposable { [weak collectionView] in
      if let collectionView = collectionView {
        objc_setAssociatedObject(collectionView, &UICollectionView.AssociatedKeys.BondDataSourceKey, nil, objc_AssociationPolicy.OBJC_ASSOCIATION_RETAIN_NONATOMIC)
      }
    }
  }
}
