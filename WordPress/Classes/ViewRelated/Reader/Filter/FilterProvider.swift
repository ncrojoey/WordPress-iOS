import WordPressFlux

class FilterProvider: Observable, FilterTabBarItem {

    enum State {
        case loading
        case ready([TableDataItem])
        case error(Error)

        var isReady: Bool {
            switch self {
            case .ready:
                return true
            case .error, .loading:
                return false
            }
        }
    }

    var title: String {
        return titleFunc(state)
    }

    var state: State = .loading {
        didSet {
            emitChange()
        }
    }

    var items: [TableDataItem] {
        switch state {
        case .loading, .error:
            return []
        case .ready(let items):
            return items
        }
    }

    let accessibilityIdentifier: String
    let cellClass: UITableViewCell.Type
    let reuseIdentifier: String
    let emptyTitle: String
    let emptyActionTitle: String
    let emptyAction: (UIViewController) -> Void

    private let titleFunc: (State?) -> String

    let changeDispatcher = Dispatcher<Void>()

    init(title: @escaping (State?) -> String,
         accessibilityIdentifier: String,
         cellClass: UITableViewCell.Type,
         reuseIdentifier: String,
         emptyTitle: String,
         emptyActionTitle: String,
         emptyAction: (@escaping (UIViewController) -> Void),
         provider: (@escaping (Result<[TableDataItem], Error>) -> Void) -> Void) {

        titleFunc = title
        self.accessibilityIdentifier = accessibilityIdentifier
        self.cellClass = cellClass
        self.reuseIdentifier = reuseIdentifier
        self.emptyTitle = emptyTitle
        self.emptyActionTitle = emptyActionTitle
        self.emptyAction = emptyAction

        provider() { [weak self] result in
            switch result {
            case .success(let items):
                self?.state = .ready(items)
            case .failure(let error):
                self?.state = .error(error)
            }
        }
    }
}

extension ReaderSiteTopic {

    static func filterProvider() -> FilterProvider {
        let titleFunction: (FilterProvider.State?) -> String = { state in
            switch state {
            case .loading, .error, .none:
                return NSLocalizedString("Sites", comment: "Sites Filter Tab Title")
            case .ready(let items):
                return String(format: NSLocalizedString("Sites (%lu)", comment: "Sites Filter Tab Title with Count"), items.count)
            }
        }

        let emptyTitle = NSLocalizedString("Add a site", comment: "No Tags View Button Label")
        let emptyActionTitle = NSLocalizedString("You can follow posts on a specific site by following it", comment: "No Sites View Label")

        return FilterProvider(title: titleFunction,
                              accessibilityIdentifier: "SitesFilterTab",
                              cellClass: SiteTableViewCell.self,
                              reuseIdentifier: "Sites",
                              emptyTitle: emptyTitle,
                              emptyActionTitle: emptyActionTitle,
                              emptyAction: showAdd,
                              provider: tableProvider)
    }

    private static func showAdd(on presenterViewController: UIViewController) {
        let presenter = ReaderManageScenePresenter(selected: .sites)
        presenter.present(on: presenterViewController, animated: true, completion: nil)
    }

    private static func tableProvider(completion: @escaping (Result<[TableDataItem], Error>) -> Void) {
        fetchFollowedSites(completion: { result in
            let itemResult = result.map { sites in
                sites.map { topic in
                    return TableDataItem(topic: topic, configure: { cell in
                        cell.textLabel?.text = topic.title
                        cell.detailTextLabel?.text = topic.siteURL
                    })
                }
            }
            completion(itemResult)
        })
    }

    private static func fetchFollowedSites(completion: @escaping (Result<[ReaderSiteTopic], Error>) -> Void) {
        let siteService = ReaderTopicService(managedObjectContext: ContextManager.sharedInstance().mainContext)

        siteService.fetchFollowedSites(success: {
            completion(.success(siteService.allSiteTopics().filter { !$0.isExternal }))
        }, failure: { error in
            let unknownRestAPIError = NSError(domain: WordPressComRestApiErrorDomain, code: -1, userInfo: nil)
            completion(.failure(error ?? unknownRestAPIError))
            DDLogError("Could not sync sites: \(String(describing: error))")
        })
    }
}

extension ReaderTagTopic {

    static func filterProvider() -> FilterProvider {
        let titleFunction: (FilterProvider.State?) -> String = { state in
            switch state {
            case .loading, .error, .none:
                return NSLocalizedString("Tags", comment: "Tags Filter Tab Title")
            case .ready(let items):
                return String(format: NSLocalizedString("Tags (%lu)", comment: "Tags Filter Tab Title with Count"), items.count)
            }
        }

        let emptyTitle = NSLocalizedString("Add a tag", comment: "No Tags View Button Label")
        let emptyActionTitle = NSLocalizedString("You can follow posts on a specific subject by adding a tag", comment: "No Tags View Label")

        return FilterProvider(title: titleFunction,
                              accessibilityIdentifier: "TagsFilterTab",
                              cellClass: UITableViewCell.self,
                              reuseIdentifier: "Tags",
                              emptyTitle: emptyTitle,
                              emptyActionTitle: emptyActionTitle,
                              emptyAction: showAdd,
                              provider: tableProvider)
    }

    private static func showAdd(on presenterViewController: UIViewController) {
        let presenter = ReaderManageScenePresenter(selected: .tags)
        presenter.present(on: presenterViewController, animated: true, completion: nil)
    }

    private static func tableProvider(completion: @escaping (Result<[TableDataItem], Error>) -> Void) {
        fetchFollowedTags(completion: { result in
            let itemResult = result.map { tags in
                tags.map { topic in
                    return TableDataItem(topic: topic, configure: { (cell) in
                        cell.textLabel?.text = topic.slug
                    })
                }
            }
            completion(itemResult)
        })
    }

    static var tagsFetchRequest: NSFetchRequest<NSFetchRequestResult> {
        let fetchRequest = NSFetchRequest<NSFetchRequestResult>(entityName: "ReaderTagTopic")
        fetchRequest.predicate = NSPredicate(format: "following == %@ AND showInMenu == YES AND type == 'tag'",
                                             NSNumber(value: ReaderHelpers.isLoggedIn()))
        fetchRequest.sortDescriptors = [NSSortDescriptor(key: "title", ascending: true, selector: #selector(NSString.localizedCaseInsensitiveCompare))]
        return fetchRequest
    }

    private static func fetchFollowedTags(completion: @escaping (Result<[ReaderTagTopic], Error>) -> Void) {
        do {
            guard let topics = try ContextManager.sharedInstance().mainContext.fetch(tagsFetchRequest) as? [ReaderTagTopic] else {
                return
            }
            completion(.success(topics))
        } catch {
            DDLogError("There was a problem fetching followed tags." + error.localizedDescription)
            completion(.failure(error))
        }
    }
}
