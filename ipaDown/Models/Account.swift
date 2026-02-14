//
//  Account.swift
//  ipaDown
//
//  Created by Shawn Rain on 2026/2/14.
//

import Foundation

/// Apple 账号信息
struct Account: Codable, Identifiable, Hashable, Equatable, Sendable {
    var id: String { email }
    
    var email: String
    var password: String
    var appleId: String
    var storeFront: String          // Store Front ID, e.g. "143441" for US
    var firstName: String
    var lastName: String
    var passwordToken: String
    var directoryServicesId: String  // dsPersonId
    var cookies: [HTTPCookieData]
    
    var displayName: String {
        "\(firstName) \(lastName)"
    }
    
    var countryCode: String? {
        CountryCodes.countryCode(for: storeFront)
    }
}

/// 可序列化的 HTTP Cookie 数据
struct HTTPCookieData: Codable, Hashable, Equatable, Sendable {
    var name: String
    var value: String
    var domain: String
    var path: String
    var isSecure: Bool
    var expiresDate: Date?
    
    init(from cookie: HTTPCookie) {
        self.name = cookie.name
        self.value = cookie.value
        self.domain = cookie.domain
        self.path = cookie.path
        self.isSecure = cookie.isSecure
        self.expiresDate = cookie.expiresDate
    }
    
    func toHTTPCookie() -> HTTPCookie? {
        var properties: [HTTPCookiePropertyKey: Any] = [
            .name: name,
            .value: value,
            .domain: domain,
            .path: path,
            .secure: isSecure ? "TRUE" : "FALSE"
        ]
        if let expires = expiresDate {
            properties[.expires] = expires
        }
        return HTTPCookie(properties: properties)
    }
}
