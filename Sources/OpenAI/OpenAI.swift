//
//  OpenAI.swift
//
//
//  Created by Sergii Kryvoblotskyi on 9/18/22.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol OpenAIDelegate: AnyObject {
    func openAI(_ openAI: OpenAI, didPrepare request: URLRequest) -> URLRequest
}

final public class OpenAI: OpenAIProtocol {
    
    public struct Configuration {
        
        /// OpenAI API token. See https://platform.openai.com/docs/api-reference/authentication
        public let token: String
        
        /// Optional OpenAI organization identifier. See https://platform.openai.com/docs/api-reference/authentication
        public let organizationIdentifier: String?
        
        /// API host. Set this property if you use some kind of proxy or your own server. Default is api.openai.com
        public let host: String
        
        /// Default request timeout
        public let timeoutInterval: TimeInterval
        
        /// api paths
        public let paths: OpenAIPaths
        
        public init(token: String, organizationIdentifier: String? = nil, host: String = "api.openai.com", timeoutInterval: TimeInterval = 60.0, paths: OpenAIPaths = OpenAIv1APIPaths()) {
            self.token = token
            self.organizationIdentifier = organizationIdentifier
            self.host = host
            self.timeoutInterval = timeoutInterval
            self.paths = paths
        }
    }
    
    private let session: URLSessionProtocol
    private var streamingSessions = ArrayWithThreadSafety<NSObject>()
    
    public let configuration: Configuration
    public weak var delegate: OpenAIDelegate?
    
    public convenience init(apiToken: String, delegate: OpenAIDelegate? = nil) {
        self.init(configuration: Configuration(token: apiToken), session: URLSession.shared, delegate: delegate)
    }
    
    public convenience init(configuration: Configuration, delegate: OpenAIDelegate? = nil) {
        self.init(configuration: configuration, session: URLSession.shared, delegate: delegate)
    }
    
    init(configuration: Configuration, session: URLSessionProtocol, delegate: OpenAIDelegate? = nil) {
        self.configuration = configuration
        self.session = session
        self.delegate = delegate
    }
    
    public convenience init(configuration: Configuration, session: URLSession = URLSession.shared, delegate: OpenAIDelegate? = nil) {
        self.init(configuration: configuration, session: session as URLSessionProtocol, delegate: delegate)
    }
    
    public func completions(query: CompletionsQuery, completion: @escaping (Result<CompletionsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<CompletionsResult>(body: query, url: buildURL(path: configuration.paths.completions)), completion: completion)
    }
    
    public func completionsStream(query: CompletionsQuery, onResult: @escaping (Result<CompletionsResult, Error>) -> Void, completion: ((Error?) -> Void)?) {
        performStreamingRequest(request: JSONRequest<CompletionsResult>(body: query.makeStreamable(), url: buildURL(path: configuration.paths.completions)), onResult: onResult, completion: completion)
    }
    
    public func images(query: ImagesQuery, completion: @escaping (Result<ImagesResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ImagesResult>(body: query, url: buildURL(path: configuration.paths.images)), completion: completion)
    }
    
    public func imageEdits(query: ImageEditsQuery, completion: @escaping (Result<ImagesResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<ImagesResult>(body: query, url: buildURL(path: configuration.paths.imageEdits)), completion: completion)
    }
    
    public func imageVariations(query: ImageVariationsQuery, completion: @escaping (Result<ImagesResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<ImagesResult>(body: query, url: buildURL(path: configuration.paths.imageVariations)), completion: completion)
    }
    
    public func embeddings(query: EmbeddingsQuery, completion: @escaping (Result<EmbeddingsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<EmbeddingsResult>(body: query, url: buildURL(path: configuration.paths.embeddings)), completion: completion)
    }
    
    public func chats(query: ChatQuery, completion: @escaping (Result<ChatResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ChatResult>(body: query, url: buildURL(path: configuration.paths.chats)), completion: completion)
    }
    
    public func chatsStream(query: ChatQuery, onResult: @escaping (Result<ChatStreamResult, Error>) -> Void, completion: ((Error?) -> Void)?) {
        performStreamingRequest(request: JSONRequest<ChatStreamResult>(body: query.makeStreamable(), url: buildURL(path: configuration.paths.chats)), onResult: onResult, completion: completion)
    }
    
    public func edits(query: EditsQuery, completion: @escaping (Result<EditsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<EditsResult>(body: query, url: buildURL(path: configuration.paths.edits)), completion: completion)
    }
    
    public func model(query: ModelQuery, completion: @escaping (Result<ModelResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModelResult>(url: buildURL(path: configuration.paths.models.withPath(query.model)), method: "GET"), completion: completion)
    }
    
    public func models(completion: @escaping (Result<ModelsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModelsResult>(url: buildURL(path: configuration.paths.models), method: "GET"), completion: completion)
    }
    
    @available(iOS 13.0, *)
    public func moderations(query: ModerationsQuery, completion: @escaping (Result<ModerationsResult, Error>) -> Void) {
        performRequest(request: JSONRequest<ModerationsResult>(body: query, url: buildURL(path: configuration.paths.moderations)), completion: completion)
    }
    
    public func audioTranscriptions(query: AudioTranscriptionQuery, completion: @escaping (Result<AudioTranscriptionResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<AudioTranscriptionResult>(body: query, url: buildURL(path: configuration.paths.audioTranscriptions)), completion: completion)
    }
    
    public func audioTranslations(query: AudioTranslationQuery, completion: @escaping (Result<AudioTranslationResult, Error>) -> Void) {
        performRequest(request: MultipartFormDataRequest<AudioTranslationResult>(body: query, url: buildURL(path: configuration.paths.audioTranslations)), completion: completion)
    }
    
    public func audioCreateSpeech(query: AudioSpeechQuery, completion: @escaping (Result<AudioSpeechResult, Error>) -> Void) {
        performSpeechRequest(request: JSONRequest<AudioSpeechResult>(body: query, url: buildURL(path: configuration.paths.audioSpeech)), completion: completion)
    }
    
}

extension OpenAI {
    
    func performRequest<ResultType: Codable>(request: any URLRequestBuildable, completion: @escaping (Result<ResultType, Error>) -> Void) {
        do {
            let buildRequest = try request.build(token: configuration.token,
                                                 organizationIdentifier: configuration.organizationIdentifier,
                                                 timeoutInterval: configuration.timeoutInterval)
            
            let request = delegate?.openAI(self, didPrepare: buildRequest) ?? buildRequest
            
            let task = session.dataTask(with: request) { data, _, error in
                if let error = error {
                    return completion(.failure(error))
                }
                guard let data = data else {
                    return completion(.failure(OpenAIError.emptyData))
                }
                let decoder = JSONDecoder()
                do {
                    completion(.success(try decoder.decode(ResultType.self, from: data)))
                } catch {
                    completion(.failure((try? decoder.decode(APIErrorResponse.self, from: data)) ?? error))
                }
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
    
    func performStreamingRequest<ResultType: Codable>(request: any URLRequestBuildable, onResult: @escaping (Result<ResultType, Error>) -> Void, completion: ((Error?) -> Void)?) {
        do {
            let buildRequest = try request.build(token: configuration.token,
                                                 organizationIdentifier: configuration.organizationIdentifier,
                                                 timeoutInterval: configuration.timeoutInterval)
            
            let request = delegate?.openAI(self, didPrepare: buildRequest) ?? buildRequest
            
            let session = StreamingSession<ResultType>(urlRequest: request)
            session.onReceiveContent = {_, object in
                onResult(.success(object))
            }
            session.onProcessingError = {_, error in
                onResult(.failure(error))
            }
            session.onComplete = { [weak self] object, error in
                self?.streamingSessions.removeAll(where: { $0 == object })
                completion?(error)
            }
            session.perform()
            streamingSessions.append(session)
        } catch {
            completion?(error)
        }
    }
    
    func performSpeechRequest(request: any URLRequestBuildable, completion: @escaping (Result<AudioSpeechResult, Error>) -> Void) {
        do {
            let buildRequest = try request.build(token: configuration.token,
                                                 organizationIdentifier: configuration.organizationIdentifier,
                                                 timeoutInterval: configuration.timeoutInterval)
            
            let request = delegate?.openAI(self, didPrepare: buildRequest) ?? buildRequest
            
            let task = session.dataTask(with: request) { data, _, error in
                if let error = error {
                    return completion(.failure(error))
                }
                guard let data = data else {
                    return completion(.failure(OpenAIError.emptyData))
                }
                
                completion(.success(AudioSpeechResult(audio: data)))
            }
            task.resume()
        } catch {
            completion(.failure(error))
        }
    }
}

extension OpenAI {
    func buildURL(path: String) -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = configuration.host
        components.path = path
        return components.url!
    }
}

public protocol OpenAIPaths {
    var completions: String { get }
    var embeddings: String { get }
    var chats: String { get }
    var edits: String { get }
    var models: String { get }
    var moderations: String { get }
    var audioSpeech: String { get }
    var audioTranscriptions: String { get }
    var audioTranslations: String { get }
    var images: String { get }
    var imageEdits: String { get }
    var imageVariations: String { get }
}

public struct OpenAIv1APIPaths: OpenAIPaths {
    public let completions = "/v1/completions"
    public let embeddings = "/v1/embeddings"
    public let chats = "/v1/chat/completions"
    public let edits = "/v1/edits"
    public let models = "/v1/models"
    public let moderations = "/v1/moderations"
    public let audioSpeech = "/v1/audio/speech"
    public let audioTranscriptions = "/v1/audio/transcriptions"
    public let audioTranslations = "/v1/audio/translations"
    public let images = "/v1/images/generations"
    public let imageEdits = "/v1/images/edits"
    public let imageVariations = "/v1/images/variations"
    
    public init() {}
}

extension String {
    func withPath(_ path: String) -> String {
        self + "/" + path
    }
}
