#!/usr/bin/env swift

import Foundation

extension Collection {
	
	/// Returns the element at the specified index if it is within bounds, otherwise nil.
	subscript(safe index: Index) -> Iterator.Element? {
		return indices.contains(index) ? self[index] : nil
	}
}

class TaxTool {
	
	let urlString = "http://qpublic9.qpublic.net/hi_hawaii_display.php"
	let countyQueryItem = URLQueryItem(name: "county", value: "hi_hawaii")
	var csvText = "tmk,mailingAddress,backTaxYears,backTaxTotal\n"
	
	// Local CVS info to write data to
	let csvName = "taxInfo.csv"
	
	var zoneNum: Int?    { didSet { try? captureUserInputFor(.section) }}
	var sectionNum: Int? { didSet { try? captureUserInputFor(.plat) }}
	var platNum: Int?    { didSet { try? captureUserInputFor(.parcel) }}
	var parcelNum: Int?  { didSet { try? setParcelString() }}
	
	typealias ParcelData = (mailing: String, location: String, taxes: String)
	
	// The value used as the query param to fetch the parcel's data
	var fullTMKString: String?
	// The returned HTML string from the given query
	var parcelHTMLContents: String?
	
	var tmks: [String]?
	var parcelData: [ParcelData] = []
	
	enum TaxError: Error {
		
		case invalidInput
		case outOfRange
		case noParcelString
		case unknown
	}
	
	enum TMKType {
		
		case zone
		case section
		case plat
		case parcel
	}
	
	private func loadTMKs() {
		let string = try? String(contentsOfFile: "./tmk.csv")
		tmks = string?.components(separatedBy: "\n")
	}
	
	private func setUpParselDataFetch(forRange: Bool = false) throws {
		
		guard let tmk = fullTMKString else { throw TaxError.noParcelString }
		
		if forRange {
			let relevantTMKs = tmks?.filter { $0.hasPrefix("3\(tmk)") }
			print("There are \(relevantTMKs?.count ?? 0) parcels within \(tmk)")
			print("Fetching parsel data for all these mofos. Hang tight...")
			relevantTMKs?.forEach { relevantTMK in
				sleep(1)
				var formattedTMK = relevantTMK
				formattedTMK.removeFirst()
				let properString = formattedTMK + "0000"
				fetchParselDataFor(properString)
			}
		} else {
			print("Fetching parsel data for TMK: \(tmk). Hang tight...")
			fetchParselDataFor(tmk)
		}
		
		let csvURL = URL(fileURLWithPath: ".").appendingPathComponent(csvName)
		try? csvText.write(to: csvURL, atomically: true, encoding: .utf8)
		
		print("All done! Open `taxInfo.csv` to see all fetched data")
	}
	
	private func fetchParselDataFor(_ tmk: String) {
		
		let queryItems = [countyQueryItem, URLQueryItem(name: "KEY", value: tmk)]
		var urlComps = URLComponents(string: urlString)
		urlComps?.queryItems = queryItems
		
		guard let url = urlComps?.url else {
			print("Could not construct URL")
			return
		}
		
		print("Grabbing data for parcel at: \(url)")
		
		if let htmlString = try? String(contentsOf: url) {
			
			guard let mailingAddress = parseMailingAddressFrom(htmlString) else { return }
			// guard let locationAddress = parseLocationAddressFrom(htmlString) else { return }
			let taxInformation = parseTaxInfoFrom(htmlString)
			
			
			let newLine = "\(tmk),\(mailingAddress),\(taxInformation.years),\(taxInformation.total)\n"
			csvText.append(newLine)
			
			print("That one went well! Onto the next...")
		} else {
			print("That one didn't work. One or more of the mailing/location/tax info wasn't found")
			return
		}
	}
	
	private func parseMailingAddressFrom(_ htmlString: String) -> String? {
		
		guard let rawMailingAddress = htmlString.components(separatedBy: "Mailing Address")[safe: 1] else { return nil }
		guard let prefixedMailingAddress = rawMailingAddress.components(separatedBy: "owner_value")[safe: 1] else { return nil }
		
		let mailingAddressComponents = prefixedMailingAddress.components(separatedBy: "&nbsp;")
		
		if let componentOne = mailingAddressComponents[safe: 1], let componentTwo = mailingAddressComponents[safe: 2] {
			let mailingAddress = (componentOne + componentTwo).replacingOccurrences(of: "<br>", with: " ").replacingOccurrences(of: ",", with: "")
			if mailingAddress.contains("Parcel Number") {
				return "No Mailing Address"
			} else {
				return mailingAddress
			}
		} else {
			return nil
		}
	}
	
	private func parseLocationAddressFrom(_ htmlString: String) -> String? {
		
		guard let rawLocationAddress = htmlString.components(separatedBy: "Location Address")[safe: 1] else { return nil }
		guard let prefixedLocationAddress = rawLocationAddress.components(separatedBy: "owner_value")[safe: 1] else { return nil }
		
		let locationAddressComponents = prefixedLocationAddress.components(separatedBy: "&nbsp;")
		
		return locationAddressComponents[safe: 1]
	}
	
	private func parseTaxInfoFrom(_ htmlString: String) -> (years: String, total: String) {
		
		let sanitizedData = htmlString.replacingOccurrences(of: "&nbsp;", with: "")
		let moreData = sanitizedData.replacingOccurrences(of: "  ", with: "")
		let rawTaxInfo = moreData.components(separatedBy: "Current Tax Bill Information")[safe: 1]
		let taxInfo = rawTaxInfo?.components(separatedBy: "</B>")[safe: 0]
		
		guard var taxRows = taxInfo?.components(separatedBy: "<tr>") else { return (years: "", total: "$0.00") }
		
		taxRows.removeFirst()
		taxRows.removeFirst()
		
		var backTaxData: [String] = taxRows.map { row in
			
			let rawValue = row.components(separatedBy: "<td class=\"sales_value\">")[safe: 1] ?? String()
			return rawValue.replacingOccurrences(of: "</td>", with: "")
				.replacingOccurrences(of: "<B>", with: "")
				.replacingOccurrences(of: " ", with: "")
		}
		
		if backTaxData.count == 0 {
			return (years: "", total: "$0.00")
		} else if backTaxData.count == 1 {
			return (years: "", total: backTaxData[0].replacingOccurrences(of: ",", with: ""))
		} else {
			let total = backTaxData.removeLast()
			let years = "\(backTaxData.first!)-\(backTaxData.last!)"
			return (years: years, total: total.replacingOccurrences(of: ",", with: ""))
		}
	}
	
	private func setParcelString() throws {
		
		guard let zone = zoneNum, let section = sectionNum, let plat = platNum, let parcel = parcelNum else {
			throw TaxError.unknown
		}
		
		let zoneString    = String(describing: zone)
		let sectionString = String(describing: section)
		var platString    = String(describing: plat)
		var parcelString  = String(describing: parcel)
		
		if platString.count == 1 { platString = "00\(platString)" }
		if platString.count == 2 { platString =  "0\(platString)" }
		
		if parcelString.count == 1 { parcelString = "00\(parcelString)" }
		if parcelString.count == 2 { parcelString =  "0\(parcelString)" }
		
		if parcelString == "1970" {
			// A parcel string was NOT inputted, use plat range to fetch parcel data
			fullTMKString = "\(zoneString)\(sectionString)\(platString)"
			try? setUpParselDataFetch(forRange: true)
		} else {
			// A parcel string was inputted, use exact value to fetch parcel data
			fullTMKString = "\(zoneString)\(sectionString)\(platString)\(parcelString)0000"
			try? setUpParselDataFetch()
		}
	}
	
	private func validated(_ input: Int, forType type: TMKType) throws -> Int {
		
		switch type {
		case .zone, .section:
			if input > 0 && input < 0010 { return input } else { throw TaxError.outOfRange }
		case .plat:
			if input > 0 && input < 1000 { return input } else { throw TaxError.outOfRange }
		case .parcel:
			if (input > 0 && input < 1000) || input == 1970 { return input } else { throw TaxError.outOfRange }
		}
	}
	
	private func captureZoneNum() throws -> Int {
		print("Enter a Hawaii (Big Island) Zone number between 1-9:")
		guard let input = Int(readLine() ?? String()) else { throw TaxError.invalidInput }
		return try validated(input, forType: .zone)
	}
	
	private func captureSectionNum() throws -> Int {
		print("Enter a Section number between 1-9:")
		guard let input = Int(readLine() ?? String()) else { throw TaxError.invalidInput }
		return try validated(input, forType: .section)
	}
	
	private func capturePlatNum() throws -> Int {
		print("Enter a Plat number between 1-999:")
		guard let input = Int(readLine() ?? String()) else { throw TaxError.invalidInput }
		return try validated(input, forType: .plat)
	}
	
	private func captureParcelNum() throws -> Int {
		print("Do you want to enter a specific parcel number? y/n:")
		let input = readLine()?.lowercased() ?? "n"
		print(input)
		if input != "y" && input != "n" {
			throw TaxError.invalidInput
		} else {
			switch input {
			case "y":
				print("Enter a Parcel number between 1-999:")
				guard let input = Int(readLine() ?? String()) else { throw TaxError.invalidInput }
				return try validated(input, forType: .parcel)
			case "n":
				return 1970 // Special value: gather tax info for all parcels within the given plat
			default:
				throw TaxError.unknown
			}
		}
	}
	
	private func captureUserInputFor(_ type: TMKType) throws {
		
		switch type {
		case .zone:    zoneNum    = try captureZoneNum()
		case .section: sectionNum = try captureSectionNum()
		case .plat:    platNum    = try capturePlatNum()
		case .parcel:  parcelNum  = try captureParcelNum()
		}
	}
	
	public func start() {
		print("Starting up...")
		
		loadTMKs()
		
		print("**********************************************************")
		print("Welcome to Andrew's special Parcel Search Command Line Tool")
		print("S")
		print("H")
		print("A")
		print("K")
		print("A")
		print("B")
		print("R")
		print("A")
		print("**********************************************************\n")
		print("This tool is currently designed for parcel searches strictly on the Big Island\n")
		
		try? captureUserInputFor(.zone)
	}
}

let taxTool = TaxTool()

taxTool.start()
