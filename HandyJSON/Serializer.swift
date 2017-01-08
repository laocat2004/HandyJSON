/*
 * Copyright 1999-2101 Alibaba Group.
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

//
//  JSONSerializer.swift
//  HandyJSON
//
//  Created by zhouzhuo on 9/30/16.
//

extension Metrizable {

    internal static func _serializeToDictionary(propertys: [(String?, Any)], headPointer: UnsafeMutableRawPointer, offsetInfo: [String: Int] , mapper: HelpingMapper) -> [String: Any] {

        var dict = [String: Any]()

        propertys.forEach { (label, value) in

            var key = label ?? ""

            guard let offset = offsetInfo[key] else {
                return
            }

            let mutablePointer = headPointer.advanced(by: offset)

            if mapper.propertyExcluded(key: mutablePointer.hashValue) {
                return
            }

            if let mappingHandler = mapper.getMappingHandler(key: mutablePointer.hashValue) {
                // if specific key is set, replace the label
                if let specifyKey = mappingHandler.mappingName {
                    key = specifyKey
                }

                if let transformer = mappingHandler.takeValueClosure {
                    if let _transformedValue = transformer(value) {
                        dict[key] = _transformedValue
                    }
                    return
                }
            }

            if let typedValue = value as? Metrizable {
                if let result = self._serialize(from: typedValue) {
                    dict[key] = result
                }
            }
        }
        return dict
    }

    internal static func _serialize(from object: Metrizable) -> Any? {
        let objectType = type(of: object)

        if let enumType = objectType as? HandyJSONEnum.Type {
            return enumType.takeValueWrapper().rawValue(fromEnum: object)
        } else if objectType is BasePropertyProtocol.Type {
            return object
        }

        let mirror = Mirror(reflecting: object)

        if objectType is ImplicitlyUnwrappedTypeProtocol.Type {
            if let _value = mirror.children.first?.value {
                if let _transformable = _value as? Metrizable {
                    return Self._serialize(from: _transformable)
                }
                return _value
            }
            return nil
        }

        guard let displayStyle = mirror.displayStyle else {
            return self
        }

        switch displayStyle {
        case .class, .struct:

            let mapper = HelpingMapper()
            // do user-specified mapping first
            if !(object is TransformableProperty) {
                return nil
            }
            var mutableObject = object as! TransformableProperty
            mutableObject.mapping(mapper: mapper)

            let rawPointer: UnsafeMutableRawPointer
            if objectType is AnyClass {
                rawPointer = UnsafeMutableRawPointer(mutableObject.headPointerOfClass())
            } else {
                rawPointer = UnsafeMutableRawPointer(mutableObject.headPointerOfStruct())
            }

            var children = [(label: String?, value: Any)]()
            let mirrorChildrenCollection = AnyRandomAccessCollection(mirror.children)!
            children += mirrorChildrenCollection

            var currentMirror = mirror
            while let superclassChildren = currentMirror.superclassMirror?.children {
                let randomCollection = AnyRandomAccessCollection(superclassChildren)!
                children += randomCollection
                currentMirror = currentMirror.superclassMirror!
            }

            var offsetInfo = [String: Int]()
            guard let properties = getProperties(forType: objectType) else {
                return nil
            }

            if let pp = getProperties(forInstance: mutableObject) {
                pp.forEach({ (ppp) in
                    print(ppp.key, ppp.value)
                })
            }

            properties.forEach({ (desc) in
                offsetInfo[desc.key] = desc.offset
            })

            return Self._serializeToDictionary(propertys: children, headPointer: rawPointer, offsetInfo: offsetInfo, mapper: mapper) as Any
        case .enum:
            return object as Any
        case .optional:
            if mirror.children.count != 0 {
                let (_, some) = mirror.children.first!
                if let _value = some as? Metrizable {
                    return Self._serialize(from: _value)
                } else {
                    return some
                }
            }
            return nil
        case .collection, .set:
            var array = [Any]()
            mirror.children.enumerated().forEach({ (index, element) in
                if let _value = element.value as? Metrizable, let transformedValue = Self._serialize(from: _value) {
                    array.append(transformedValue)
                }
            })
            return array as Any
        case .dictionary:
            var dict = [String: Any]()
            mirror.children.enumerated().forEach({ (index, element) in
                let _mirror = Mirror(reflecting: element.value)
                var key: String?
                var value: Any?
                _mirror.children.enumerated().forEach({ (_index, _element) in
                    if _index == 0 {
                        key = "\(_element.value)"
                    } else {
                        if let _value = _element.value as? Metrizable {
                            value = Self._serialize(from: _value)
                        }
                    }
                })
                if (key ?? "") != "" && value != nil {
                    dict[key!] = value!
                }
            })
            return dict as Any
        default:
            return object as Any
        }
    }
}


public extension HandyJSON {

    public func toJSON() -> [String: Any]? {

        if let dict = Self._serialize(from: self) as? [String: Any] {
            return dict
        }
        return nil
    }

    public func toJSONString(prettyPrint: Bool = false) -> String? {

        if let anyObject = Self._serialize(from: self) {
            if JSONSerialization.isValidJSONObject(anyObject) {
                do {
                    let jsonData: Data
                    if prettyPrint {
                        jsonData = try JSONSerialization.data(withJSONObject: anyObject, options: [.prettyPrinted])
                    } else {
                        jsonData = try JSONSerialization.data(withJSONObject: anyObject, options: [])
                    }
                    return String(data: jsonData, encoding: .utf8)
                } catch let error {
                    print(error)
                }
            }
        }
        return nil
    }
}

public extension Array where Element: HandyJSON {

    public func toJSON() -> [[String: Any]?] {

        return self.map({ (object) -> [String: Any]? in
            return Element._serialize(from: object) as? [String: Any]
        })
    }

    public func toJSONString(prettyPrint: Bool = false) -> String? {

        let anyArray = self.map({ (object) -> [String: Any]? in
            return Element._serialize(from: object) as? [String: Any]
        })
        if JSONSerialization.isValidJSONObject(anyArray) {
            do {
                let jsonData: Data
                if prettyPrint {
                    jsonData = try JSONSerialization.data(withJSONObject: anyArray, options: [.prettyPrinted])
                } else {
                    jsonData = try JSONSerialization.data(withJSONObject: anyArray, options: [])
                }
                return String(data: jsonData, encoding: .utf8)
            } catch let error {
                print(error)
            }
        }
        return nil
    }
}

public extension Set where Element: HandyJSON {

    public func toJSON() -> [[String: Any]?] {

        return self.map({ (object) -> [String: Any]? in
            return Element._serialize(from: object) as? [String: Any]
        })
    }

    public func toJSONString(prettyPrint: Bool = false) -> String? {

        let anyArray = self.map({ (object) -> [String: Any]? in
            return Element._serialize(from: object) as? [String: Any]
        })
        if JSONSerialization.isValidJSONObject(anyArray) {
            do {
                let jsonData: Data
                if prettyPrint {
                    jsonData = try JSONSerialization.data(withJSONObject: anyArray, options: [.prettyPrinted])
                } else {
                    jsonData = try JSONSerialization.data(withJSONObject: anyArray, options: [])
                }
                return String(data: jsonData, encoding: .utf8)
            } catch let error {
                print(error)
            }
        }
        return nil
    }
}


//////////// the below APIs is deprecated ///////////////

public protocol ModelTransformerProtocol {

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toPrettifyJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toSimpleDictionary() -> [String: Any]?
}

public protocol ArrayTransformerProtocol {

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toPrettifyJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toSimpleArray() -> [Any]?
}

public protocol DictionaryTransformerProtocol {

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toPrettifyJSON() -> String?

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    func toSimpleDictionary() -> [String: Any]?
}

class GenericObjectTransformer: ModelTransformerProtocol, ArrayTransformerProtocol, DictionaryTransformerProtocol {

    private var object: Any?

    init(of object: Any?) {
        self.object = object
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public func toSimpleArray() -> [Any]? {
        if let _object = self.object, let result = GenericObjectTransformer.transformToSimpleObject(object: _object) {
            return result as? [Any]
        }
        return nil
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public func toSimpleDictionary() -> [String: Any]? {
        if let _object = self.object, let result = GenericObjectTransformer.transformToSimpleObject(object: _object) {
            return result as? [String: Any]
        }
        return nil
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public func toJSON() -> String? {
        if let _object = self.object, let result = GenericObjectTransformer.transformToSimpleObject(object: _object) {
            return GenericObjectTransformer.transformSimpleObjectToJSON(object: result)
        }
        return nil
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public func toPrettifyJSON() -> String? {
        if let result = toJSON() {
            let jsonData = result.data(using: String.Encoding.utf8)!
            if let jsonObject = try? JSONSerialization.jsonObject(with: jsonData, options: [.allowFragments]) as AnyObject, let prettyJsonData = try? JSONSerialization.data(withJSONObject: jsonObject, options: .prettyPrinted) {
                return NSString(data: prettyJsonData, encoding: String.Encoding.utf8.rawValue)! as String
            }
        }
        return nil
    }
}

extension GenericObjectTransformer {

    static func transformToSimpleObject(object: Any) -> Any? {
        if (type(of: object) is BasePropertyProtocol.Type) {
            return object
        }

        let mirror = Mirror(reflecting: object)

        guard let displayStyle = mirror.displayStyle else {
            return object
        }

        switch displayStyle {
        case .class, .struct:
            var children = [(label: String?, value: Any)]()
            let mirrorChildrenCollection = AnyRandomAccessCollection(mirror.children)!
            children += mirrorChildrenCollection

            var currentMirror = mirror
            while let superclassChildren = currentMirror.superclassMirror?.children {
                let randomCollection = AnyRandomAccessCollection(superclassChildren)!
                children += randomCollection
                currentMirror = currentMirror.superclassMirror!
            }

            var dict = [String: Any]()
            children.enumerated().forEach({ (index, element) in
                let key = element.label ?? ""
                let handledValue = transformToSimpleObject(object: element.value)
                if key != "" && handledValue != nil {
                    dict[key] = handledValue
                }
            })

            return dict as Any
        case .enum:
            return object as Any
        case .optional:
            if mirror.children.count != 0 {
                let (_, some) = mirror.children.first!
                return transformToSimpleObject(object: some)
            } else {
                return nil
            }
        case .collection, .set:
            var array = [Any]()
            mirror.children.enumerated().forEach({ (index, element) in
                if let transformValue = transformToSimpleObject(object: element.value) {
                    array.append(transformValue)
                }
            })
            return array as Any
        case .dictionary:
            var dict = [String: Any]()
            mirror.children.enumerated().forEach({ (index, element) in
                let _mirror = Mirror(reflecting: element.value)
                var key: String?
                var value: Any?
                _mirror.children.enumerated().forEach({ (_index, _element) in
                    if _index == 0 {
                        key = "\(_element.value)"
                    } else {
                        value = transformToSimpleObject(object: _element.value)
                    }
                })
                if (key ?? "") != "" && value != nil {
                    dict[key!] = value!
                }
            })
            return dict as Any
        default:
            return object
        }
    }

    static func transformSimpleObjectToJSON(object: Any) -> String {
        let objectType: Any.Type = type(of: object)

        switch objectType {
        case is String.Type, is NSString.Type:
            let json = "\"" + String(describing: object)  + "\""
            return json
        case is BasePropertyProtocol.Type:
            let json = String(describing: object)
            return json
        case is ArrayTypeProtocol.Type:
            let array = object as! [Any]
            var json = ""
            array.enumerated().forEach({ (index, element) in
                if index != 0 {
                    json += ","
                }
                json += transformSimpleObjectToJSON(object: element)
            })
            return "[" + json + "]"
        case is DictionaryTypeProtocol.Type:
            let dict = object as! [String: Any]
            var json = ""
            dict.enumerated().forEach({ (index, kv) in
                if index != 0 {
                    json += ","
                }
                json += "\"\(kv.key)\":\(transformSimpleObjectToJSON(object: kv.value))"
            })
            return "{" + json + "}"
        default:
            return "\"\(String(describing: object))\""
        }
    }
}

public class JSONSerializer {

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(model: Any?) -> ModelTransformerProtocol {
        return GenericObjectTransformer(of: model)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(model: AnyObject?) -> ModelTransformerProtocol {
        return GenericObjectTransformer(of: model)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(array: [Any]?) -> ArrayTransformerProtocol {
        return GenericObjectTransformer(of: array)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(array: [AnyObject]?) -> ArrayTransformerProtocol {
        return GenericObjectTransformer(of: array)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(array: NSArray?) -> ArrayTransformerProtocol {
        return GenericObjectTransformer(of: array)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(dict: [String: Any]?) -> DictionaryTransformerProtocol {
        return GenericObjectTransformer(of: dict)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(dict: [String: AnyObject]?) -> DictionaryTransformerProtocol {
        return GenericObjectTransformer(of: dict)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serialize(dict: NSDictionary?) -> DictionaryTransformerProtocol {
        return GenericObjectTransformer(of: dict)
    }

    @available(*, deprecated, message: "This method will be removed in the future, see the replacement serialization methods at: https://github.com/alibaba/handyjson")
    public static func serializeToJSON(object: Any?, prettify: Bool = false) -> String? {
        if prettify {
            return JSONSerializer.serialize(model: object).toPrettifyJSON()
        }
        return JSONSerializer.serialize(model: object).toJSON()
    }
}
