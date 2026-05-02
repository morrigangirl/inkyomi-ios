import Foundation

struct SavedSearchesRepositoryImpl: SavedSearchesRepository, Sendable {
    private let api: SavedSearchesAPIService

    init(api: SavedSearchesAPIService) {
        self.api = api
    }

    func list() async throws -> [SavedSearch] {
        try await api.list().data.map { $0.toDomain() }
    }

    func create(
        name: String,
        query: String?,
        filters: SearchFilters,
        sort: SearchSortOrder?
    ) async throws -> SavedSearch {
        let dto = try await api.create(
            CreateSavedSearchRequestDto(
                name: name,
                query: query,
                filters: filters.toJSONObject(),
                sort: sort?.wire
            )
        )
        return dto.toDomain()
    }

    func update(
        id: String,
        name: String? = nil,
        query: String? = nil,
        filters: SearchFilters? = nil,
        sort: SearchSortOrder? = nil
    ) async throws -> SavedSearch {
        let dto = try await api.update(
            id: id,
            UpdateSavedSearchRequestDto(
                name: name,
                query: query,
                filters: filters?.toJSONObject(),
                sort: sort?.wire
            )
        )
        return dto.toDomain()
    }

    func delete(id: String) async throws {
        try await api.delete(id: id)
    }
}

// MARK: - DTO ↔ Domain

private extension SavedSearchDto {
    func toDomain() -> SavedSearch {
        SavedSearch(
            id: id,
            name: name,
            query: query,
            filters: filters.toSearchFilters(),
            sort: sort.flatMap { SearchSortOrder.fromWire($0) },
            createdAt: createdAt,
            updatedAt: updatedAt
        )
    }
}

// MARK: - SearchFilters ↔ AnyJSONObject

extension SearchFilters {
    /// Encode the filter state into the backend's opaque jsonb blob.
    /// Only fields with non-default values are emitted to keep the
    /// payload compact.
    func toJSONObject() -> AnyJSONObject {
        var values: [String: AnyJSONValue] = [:]

        var tagSlugObj: [String: AnyJSONValue] = [:]
        for (type, slugs) in tagSlugs where !slugs.isEmpty {
            tagSlugObj[type.wire] = .array(slugs.map { .string($0) })
        }
        if !tagSlugObj.isEmpty {
            values["tagSlugs"] = .object(tagSlugObj)
        }

        if let authorId { values["authorId"] = .string(authorId) }
        if let seriesId { values["seriesId"] = .string(seriesId) }
        if let characterId { values["characterId"] = .string(characterId) }
        if let priceMin { values["priceMin"] = .double(priceMin) }
        if let priceMax { values["priceMax"] = .double(priceMax) }
        if let ratingMin { values["ratingMin"] = .double(ratingMin) }
        if !language.isEmpty {
            values["language"] = .array(language.map { .string($0) })
        }
        if let hasContentWarning { values["hasContentWarning"] = .bool(hasContentWarning) }
        if let spiceLevelMax { values["spiceLevelMax"] = .int(spiceLevelMax) }

        return AnyJSONObject(values)
    }
}

extension AnyJSONObject {
    func toSearchFilters() -> SearchFilters {
        var filters = SearchFilters()

        if let tagSlugs = values["tagSlugs"]?.asObject {
            var byType: [TagType: [String]] = [:]
            for (typeWire, slugsValue) in tagSlugs {
                guard let type = TagType.fromWire(typeWire),
                      let slugsArr = slugsValue.asArray else { continue }
                let slugs = slugsArr.compactMap { $0.asString }
                if !slugs.isEmpty { byType[type] = slugs }
            }
            filters.tagSlugs = byType
        }
        filters.authorId = values["authorId"]?.asString
        filters.seriesId = values["seriesId"]?.asString
        filters.characterId = values["characterId"]?.asString
        filters.priceMin = values["priceMin"]?.asDouble
        filters.priceMax = values["priceMax"]?.asDouble
        filters.ratingMin = values["ratingMin"]?.asDouble
        if let lang = values["language"]?.asArray {
            filters.language = lang.compactMap { $0.asString }
        }
        filters.hasContentWarning = values["hasContentWarning"]?.asBool
        filters.spiceLevelMax = values["spiceLevelMax"]?.asInt

        return filters
    }
}
