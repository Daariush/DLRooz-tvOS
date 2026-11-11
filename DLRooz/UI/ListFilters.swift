import SwiftUI

/// Films / Series filters, run through the site's own advanced search
/// (`/archive/advancedSearch/?genre=…&type=…&imdb=…&order=…&from=…&to=…`), so they cover the whole
/// catalogue and page like any other list.
struct ListFilters: Equatable {
    var genre: Int?
    var years: YearRange = .all
    /// IMDb minimum ×10 (e.g. 75 = 7.5).
    var minIMDb: Int?
    var sort: Sort = .release

    var isDefault: Bool { self == ListFilters() }

    func path(type: String) -> String {
        let q: [(String, String)] = [
            ("genre", genre.map(String.init) ?? "all"), ("genre2", "all"), ("country", "all"), ("language", "all"),
            ("type", type), ("imdb", minIMDb.map(String.init) ?? "all"), ("subtitle", "both"), ("dubbed", "both"),
            ("quality", "all"), ("order", sort.rawValue), ("from", String(years.from)), ("to", String(years.to)),
        ]
        return "/archive/advancedSearch/?" + q.map { "\($0.0)=\($0.1)" }.joined(separator: "&")
    }

    enum Sort: String, CaseIterable {
        case release, updated, rating, usersRating, metascore, votes
        var label: String {
            switch self {
            case .release: return L("تاریخ اکران", "Release date")
            case .updated: return L("آخرین آپدیت", "Recently updated")
            case .rating: return L("امتیاز IMDb", "IMDb rating")
            case .usersRating: return L("امتیاز کاربران", "Users' rating")
            case .metascore: return L("امتیاز منتقدین", "Critics' rating")
            case .votes: return L("تعداد رای", "Most votes")
            }
        }
    }

    struct YearRange: Hashable {
        let from: Int
        let to: Int
        static let all = YearRange(from: 1900, to: 2100)

        var label: String {
            if self == .all { return L("همه سال‌ها", "All years") }
            if from == to { return L(N(from), String(from)) }
            if from == 1900 { return L("قبل از \(N(to + 1))", "Before \(to + 1)") }
            if to - from == 9 && from % 10 == 0 { return L("دهه \(N(from))", "\(from)s") }
            return L("\(N(from))–\(N(to))", "\(from)–\(to)")
        }

        static var options: [YearRange] {
            let now = Calendar.current.component(.year, from: Date())
            let recent = (0..<7).map { YearRange(from: now - $0, to: now - $0) }
            let lastSingle = now - 6
            let decadeStart = (lastSingle - 1) / 10 * 10
            var out = [YearRange.all] + recent
            if lastSingle - 1 >= decadeStart { out.append(YearRange(from: decadeStart, to: lastSingle - 1)) }
            for d in stride(from: decadeStart - 10, through: 1980, by: -10) { out.append(YearRange(from: d, to: d + 9)) }
            out.append(YearRange(from: 1900, to: 1979))
            return out
        }
    }

    static let imdbOptions: [Int?] = [nil, 90, 85, 80, 75, 70, 65, 60, 50]

    static func imdbLabel(_ v: Int?) -> String {
        guard let v else { return L("هر امتیاز IMDb", "Any IMDb rating") }
        let s = v % 10 == 0 ? String(v / 10) : String(format: "%.1f", Double(v) / 10)
        return L("IMDb حداقل \(s.persianDigits)", "IMDb \(s)+")
    }

    /// The site's genre ids.
    static let genres: [(id: Int, fa: String, en: String)] = [
        (1, "اکشن", "Action"), (2, "ماجراجویی", "Adventure"), (3, "انیمیشن", "Animation"), (4, "زندگی نامه", "Biography"),
        (5, "کمدی", "Comedy"), (6, "جنایی", "Crime"), (7, "مستند", "Documentary"), (8, "درام", "Drama"),
        (9, "خانوادگی", "Family"), (10, "فانتزی", "Fantasy"), (11, "تاریخی", "History"), (12, "ترسناک", "Horror"),
        (13, "موسیقی", "Music"), (14, "موزیکال", "Musical"), (15, "معمایی", "Mystery"), (16, "عاشقانه", "Romance"),
        (17, "علمی-تخیلی", "Sci-Fi"), (18, "ورزشی", "Sport"), (19, "هیجان انگیز", "Thriller"), (20, "جنگی", "War"),
        (21, "وسترن", "Western"), (22, "کوتاه", "Short"), (24, "اجتماعی", "Social"), (25, "طنز", "Satire"),
        (26, "گفتگوی تلویزیونی", "Talk-Show"), (28, "Reality-TV", "Reality-TV"), (30, "نوآر", "Film-Noir"),
        (31, "خبری", "News"), (33, "Game-Show", "Game-Show"), (34, "حیات وحش", "Wildlife"), (35, "استندآپ", "Stand-Up"),
        (36, "تئاتر", "Theatre"),
    ]

    static func genreLabel(_ id: Int?) -> String {
        guard let id, let g = genres.first(where: { $0.id == id }) else { return L("همه ژانرها", "All genres") }
        return L(g.fa, g.en)
    }
}

/// One filter as a pop-up menu button, with a checkmark on the current choice.
struct FilterMenu<T: Equatable>: View {
    let options: [T]
    @Binding var selection: T
    let label: (T) -> String
    let icon: String

    var body: some View {
        Menu {
            ForEach(options.indices, id: \.self) { i in
                let option = options[i]
                Button {
                    selection = option
                } label: {
                    if option == selection { Label(label(option), systemImage: "checkmark") } else { Text(label(option)) }
                }
            }
        } label: {
            Label(label(selection), systemImage: icon)
        }
        .menuStyle(.button)
        .buttonStyle(TVButtonStyle())
    }
}
