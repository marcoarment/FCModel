//
//  FCModel+BindableObject.swift
//
//  Created by Marco Arment on 10/28/20.
//  Copyright © 2020 Marco Arment. See included LICENSE file.
//

import Foundation
import Combine
import ObjectiveC

extension FCModel : ObservableObject, Identifiable {
    public var objectWillChange: ObservableObjectPublisher {
        get {
            let key = UnsafeRawPointer(method(for: #selector(__observableObjectPropertiesWillChange)))!
            if let obj = objc_getAssociatedObject(self, key) as? ObservableObjectPublisher { return obj }
            let obj = ObservableObjectPublisher()
            objc_setAssociatedObject(self, key, obj, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return obj
        }
    }

    // Called from FCModel::observableObjectPropertiesWillChange
    @objc private func __observableObjectPropertiesWillChange() {
        objectWillChange.send()
    }
}

class FCModelCollection<T: FCModel> : ObservableObject {
    @Published var instances: [T]
    
    private var fetcher: (() -> [T])
    private var ignoreChangedFields: Set<String>?
    private var onlyIfChangedFields: Set<String>?

    init() {
        self.fetcher = { T.allInstances() as! [T] }
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(where whereClause: String?, arguments: [Any]?) {
        fetcher = { return T.instancesWhere(whereClause ?? "", arguments: arguments ?? []) as! [T] }
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(_ fetcher: @escaping (() -> [T])) {
        self.fetcher = fetcher
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(onlyIfChangedFields: [String]) {
        self.fetcher = { T.allInstances() as! [T] }
        self.onlyIfChangedFields = Set(onlyIfChangedFields);
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(onlyIfChangedFields: [String], _ fetcher: @escaping (() -> [T])) {
        self.fetcher = fetcher
        self.onlyIfChangedFields = Set(onlyIfChangedFields);
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(ignoringChangesInFields: [String]) {
        self.fetcher = { T.allInstances() as! [T] }
        self.ignoreChangedFields = Set(ignoringChangesInFields);
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    init(ignoringChangesInFields: [String], _ fetcher: @escaping (() -> [T])) {
        self.fetcher = fetcher
        self.ignoreChangedFields = Set(ignoringChangesInFields);
        instances = fetcher()
        NotificationCenter.default.addObserver(self, selector: #selector(fcModelChanged), name: NSNotification.Name.FCModelChange, object: T.self)
    }

    @objc func fcModelChanged(_ notification: Notification) {
        if let changedFields = notification.userInfo?[FCModelChangedFieldsKey] as? Set<String> {
            if let ignored = ignoreChangedFields, changedFields.subtracting(ignored).count == 0 { return }
            if let only = onlyIfChangedFields, changedFields.intersection(only).count == 0 { return }
        }

        self.instances = fetcher()
    }
}
