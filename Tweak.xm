#import <UIKit/UIKit.h>
#import <Foundation/Foundation.h>
#import <CoreFoundation/CoreFoundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <Security/Security.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <mach-o/loader.h>
#import <mach-o/nlist.h>
#import <mach/mach.h>
#import <mach/vm_map.h>
#import <dlfcn.h>
#import <sqlite3.h>
#import <string.h>
#import <stdlib.h>

#ifndef SEG_DATA_CONST
#define SEG_DATA_CONST "__DATA_CONST"
#endif

@interface LSApplicationProxy : NSObject
+ (instancetype)bundleProxyForCurrentProcess;
- (NSDictionary *)entitlements;
@end

@interface UIView (Private)
- (UIViewController *)_viewControllerForAncestor;
@end

@interface MSGInboxUnit : NSObject
- (NSString *)key;
@end

@interface MSGInboxRowUnit : NSObject
- (MSGInboxUnit *)inboxUnit;
@end

@interface MSGThreadListDataSource : NSObject
- (NSArray *)inboxRows;
- (NSArray *)inboxPYMKUserModels;
@end

@interface MSGHighlightsTabPeopleYouMayKnowFeedItemContentView : UIView
- (void)_setUpPymkView;
@end

@interface LSComposerCollapseBehavior : NSObject
- (void)renderComposerBarForState:(NSInteger)state;
- (void)_updateTextViewForComposerBarState:(NSInteger)state;
@end

@interface LSComposerViewController : UIViewController
- (LSComposerCollapseBehavior *)composerBarCollapseBehavior;
- (void)lsTextViewDidUpdateText:(UITextView *)textView isProgrammatically:(BOOL)isProgrammatically;
- (void)updateComposerPlaceholderTextForExpandedState;
- (void)_didPressEmojiButton:(id)sender;
- (void)_didPressOtherActionButton;
@end

@interface MSGThreadViewController : UIViewController
@end

@interface MSGMessageListViewController : UIViewController
@end

@interface MSGTempMessageListItemModel : NSObject
- (BOOL)isTombstoned;
- (BOOL)isMediaGapTombstoned;
- (BOOL)isNoteTombstoned;
- (BOOL)isSpectraTombstoned;
@end

@interface MSGTempMessageAttachmentListItemModel : NSObject
- (BOOL)isTombstoned;
@end

@interface LSMediaItem : NSObject
- (NSInteger)mediaType;
- (NSString *)mediaUrl;
@end

@interface LSStoryBucketViewController : UIViewController
- (void)startTimer;
- (void)videoDidPlayToEnd:(id)arg1;
- (void)playFromBeginningWhenPossible;
- (void)didFullyDisplayBucket;
@end

@interface LSMediaViewController : UIViewController
- (BOOL)canSaveMedia;
- (BOOL)canForwardMedia;
- (BOOL)canShareMedia;
@end

@interface LSStoryOverlayProfileView : UIView
- (void)setActionHandler:(void (^)(UIAlertController *))actionHandler;
@end

@interface MDSTabBarItemProps : NSObject
- (NSString *)accessibilityIdentifierText;
@end

@interface MDSTabBarItem : UITabBarItem
- (MDSTabBarItemProps *)props;
- (UIView *)view;
@end

@interface LSTargetAction : NSObject
- (void)handle:(id)sender;
@end

@interface MSGSettingsViewController : UIViewController
- (void)msngrButtonTapped:(id)sender;
@end

@interface MSGCommunityListViewController : UIViewController
- (void)msngrButtonTapped:(id)sender;
@end

static NSString *gCrashLogFilePath = nil;
static NSMutableString *gCrashLogBuffer = nil;
static BOOL gAntiUnsend = NO;
static __weak UITabBar *gActiveTabBar = nil;

static NSString *FlowEnsureLogFilePath(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setDateFormat:@"yyyyMMddHHmmss"];
        NSString *timestamp = [formatter stringFromDate:[NSDate date]];
        NSString *fileName = [NSString stringWithFormat:@"%@-crash.txt", timestamp];
        NSString *docsDir = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"];
        [[NSFileManager defaultManager] createDirectoryAtPath:docsDir withIntermediateDirectories:YES attributes:nil error:nil];
        gCrashLogFilePath = [docsDir stringByAppendingPathComponent:fileName];
        gCrashLogBuffer = [[NSMutableString alloc] init];
    });
    return gCrashLogFilePath;
}

static void FlowWriteLog(NSString *message) {
    if (!message) return;
    NSString *path = FlowEnsureLogFilePath();
    NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
    [formatter setDateFormat:@"yyyy-MM-dd HH:mm:ss.SSS"];
    NSString *line = [NSString stringWithFormat:@"[%@] %@\n", [formatter stringFromDate:[NSDate date]], message];
    @synchronized (gCrashLogBuffer) {
        [gCrashLogBuffer appendString:line];
        [gCrashLogBuffer writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

static void FlowUncaughtExceptionHandler(NSException *exception) {
    NSString *report = [NSString stringWithFormat:@"EXCEPTION: %@\nReason: %@\nUserInfo: %@\nStack:\n%@\n",
                        exception.name,
                        exception.reason,
                        exception.userInfo,
                        [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    FlowWriteLog(report);
}

static void FlowInstallCrashHandlers(void) {
    FlowWriteLog(@"Flow diagnostic logger started");
    NSSetUncaughtExceptionHandler(&FlowUncaughtExceptionHandler);
}

static char *FlowReplaceSubstring(const char *haystack, const char *needle, const char *replacement) {
    const char *pos = strstr(haystack, needle);
    if (!pos) return NULL;
    size_t prefixLen = (size_t)(pos - haystack);
    size_t needleLen = strlen(needle);
    size_t replLen = strlen(replacement);
    size_t suffixLen = strlen(pos + needleLen);
    char *out = (char *)malloc(prefixLen + replLen + suffixLen + 1);
    if (!out) return NULL;
    memcpy(out, haystack, prefixLen);
    memcpy(out + prefixLen, replacement, replLen);
    memcpy(out + prefixLen + replLen, pos + needleLen, suffixLen + 1);
    return out;
}

static int (*orig_sqlite3_prepare_v2)(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail) = NULL;

static int hook_sqlite3_prepare_v2(sqlite3 *db, const char *zSql, int nByte, sqlite3_stmt **ppStmt, const char **pzTail) {
    char *allocatedSql = NULL;
    if (gAntiUnsend && zSql) {
        if (strncmp(zSql, "UPDATE client_messages SET is_hidden = 1, is_tombstoned = 1", 59) == 0) {
            char *step1 = FlowReplaceSubstring(zSql, "is_hidden = 1, is_tombstoned = 1", "is_hidden = 0, is_tombstoned = 0");
            if (step1) {
                char *step2 = FlowReplaceSubstring(
                    step1,
                    "text = NULL WHERE pk = ?",
                    "text = (IFNULL(text || char(10), '') || '[Unsent Message]') WHERE pk = ? AND (text IS NULL OR text NOT LIKE '%[Unsent Message]%')"
                );
                if (step2) {
                    free(step1);
                    allocatedSql = step2;
                } else {
                    allocatedSql = step1;
                }
                zSql = allocatedSql;
                nByte = -1;
            }
        } else if (strncmp(zSql, "DELETE FROM attachments WHERE", 29) == 0 ||
                   strncmp(zSql, "DELETE FROM client_attachments WHERE message_pk", 47) == 0) {
            size_t len = strlen(zSql);
            allocatedSql = (char *)malloc(len + 7);
            if (allocatedSql) {
                memcpy(allocatedSql, zSql, len);
                memcpy(allocatedSql + len, " AND 0", 7);
                zSql = allocatedSql;
                nByte = -1;
            }
        }
    }
    int rc = orig_sqlite3_prepare_v2 ? orig_sqlite3_prepare_v2(db, zSql, nByte, ppStmt, pzTail) : SQLITE_ERROR;
    if (allocatedSql) {
        free(allocatedSql);
    }
    return rc;
}

static void FlowRebindSection(const struct section_64 *section,
                              intptr_t slide,
                              struct nlist_64 *symtab,
                              char *strtab,
                              uint32_t *indirect_symtab,
                              const char *targetName,
                              void *replacement,
                              void **origOut) {
    const bool isDataConst = strcmp(section->segname, SEG_DATA_CONST) == 0;
    uint32_t *indirect_symbol_indices = indirect_symtab + section->reserved1;
    void **indirect_symbol_bindings = (void **)((uintptr_t)slide + section->addr);
    vm_prot_t oldProtection = VM_PROT_READ;
    if (isDataConst) {
        vm_protect(mach_task_self(), (vm_address_t)indirect_symbol_bindings, section->size, FALSE, VM_PROT_READ | VM_PROT_WRITE | VM_PROT_COPY);
    }
    size_t count = section->size / sizeof(void *);
    for (size_t i = 0; i < count; i++) {
        uint32_t symtab_index = indirect_symbol_indices[i];
        if (symtab_index == INDIRECT_SYMBOL_ABS ||
            symtab_index == INDIRECT_SYMBOL_LOCAL ||
            symtab_index == (INDIRECT_SYMBOL_LOCAL | INDIRECT_SYMBOL_ABS)) {
            continue;
        }
        uint32_t strtab_offset = symtab[symtab_index].n_un.n_strx;
        char *symbol_name = strtab + strtab_offset;
        if (symbol_name[0] == '_' && strcmp(&symbol_name[1], targetName) == 0) {
            if (origOut && *origOut == NULL && indirect_symbol_bindings[i] != replacement) {
                *origOut = indirect_symbol_bindings[i];
            }
            indirect_symbol_bindings[i] = replacement;
        }
    }
    if (isDataConst) {
        vm_protect(mach_task_self(), (vm_address_t)indirect_symbol_bindings, section->size, FALSE, oldProtection);
    }
}

static void FlowRebindImage(const struct mach_header *header, intptr_t slide) {
    if (header->magic != MH_MAGIC_64) return;
    const struct mach_header_64 *header64 = (const struct mach_header_64 *)header;
    struct segment_command_64 *linkedit_segment = NULL;
    struct symtab_command *symtab_cmd = NULL;
    struct dysymtab_command *dysymtab_cmd = NULL;

    uintptr_t cur = (uintptr_t)header64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_LINKEDIT) == 0) {
                linkedit_segment = seg;
            }
        } else if (lc->cmd == LC_SYMTAB) {
            symtab_cmd = (struct symtab_command *)lc;
        } else if (lc->cmd == LC_DYSYMTAB) {
            dysymtab_cmd = (struct dysymtab_command *)lc;
        }
        cur += lc->cmdsize;
    }

    if (!linkedit_segment || !symtab_cmd || !dysymtab_cmd || !dysymtab_cmd->nindirectsyms) {
        return;
    }

    uintptr_t linkedit_base = (uintptr_t)slide + linkedit_segment->vmaddr - linkedit_segment->fileoff;
    struct nlist_64 *symtab = (struct nlist_64 *)(linkedit_base + symtab_cmd->symoff);
    char *strtab = (char *)(linkedit_base + symtab_cmd->stroff);
    uint32_t *indirect_symtab = (uint32_t *)(linkedit_base + dysymtab_cmd->indirectsymoff);

    cur = (uintptr_t)header64 + sizeof(struct mach_header_64);
    for (uint32_t i = 0; i < header64->ncmds; i++) {
        struct load_command *lc = (struct load_command *)cur;
        if (lc->cmd == LC_SEGMENT_64) {
            struct segment_command_64 *seg = (struct segment_command_64 *)lc;
            if (strcmp(seg->segname, SEG_DATA) == 0 || strcmp(seg->segname, SEG_DATA_CONST) == 0) {
                for (uint32_t j = 0; j < seg->nsects; j++) {
                    struct section_64 *sect = (struct section_64 *)((uintptr_t)seg + sizeof(struct segment_command_64)) + j;
                    uint8_t type = sect->flags & SECTION_TYPE;
                    if (type == S_LAZY_SYMBOL_POINTERS || type == S_NON_LAZY_SYMBOL_POINTERS) {
                        FlowRebindSection(sect, slide, symtab, strtab, indirect_symtab, "sqlite3_prepare_v2", (void *)&hook_sqlite3_prepare_v2, (void **)&orig_sqlite3_prepare_v2);
                    }
                }
            }
        }
        cur += lc->cmdsize;
    }
}

typedef void (*FlowMSHookFunction_t)(void *symbol, void *replace, void **result);

static void FlowHookSymbolIfPossible(void *sym, void *replace, void **origOut) {
    if (!sym) return;
    FlowMSHookFunction_t msHook = (FlowMSHookFunction_t)dlsym(RTLD_DEFAULT, "MSHookFunction");
    if (msHook) {
        msHook(sym, replace, origOut);
    }
}

static void FlowInstallSqliteAntiUnsendHook(void) {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *sym = dlsym(RTLD_DEFAULT, "sqlite3_prepare_v2");
        if (sym) {
            orig_sqlite3_prepare_v2 = (int (*)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **))sym;
            FlowHookSymbolIfPossible(sym, (void *)&hook_sqlite3_prepare_v2, (void **)&orig_sqlite3_prepare_v2);
        }
        _dyld_register_func_for_add_image(&FlowRebindImage);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            NSString *fwDir = [[[NSBundle mainBundle] bundlePath] stringByAppendingString:@"/Frameworks"];
            dlopen([[fwDir stringByAppendingString:@"/LightSpeedEngine.framework/LightSpeedEngine"] UTF8String], RTLD_NOW);
            dlopen([[fwDir stringByAppendingString:@"/LightSpeedCore.framework/LightSpeedCore"] UTF8String], RTLD_NOW);
            void *lateSym = dlsym(RTLD_DEFAULT, "sqlite3_prepare_v2");
            if (lateSym && (void *)orig_sqlite3_prepare_v2 == lateSym) {
                FlowHookSymbolIfPossible(lateSym, (void *)&hook_sqlite3_prepare_v2, (void **)&orig_sqlite3_prepare_v2);
            }
            uint32_t count = _dyld_image_count();
            for (uint32_t i = 0; i < count; i++) {
                FlowRebindImage(_dyld_get_image_header(i), _dyld_get_image_vmaddr_slide(i));
            }
        });
    });
}

@interface NSBundle (Msngr)
+ (NSBundle *)msngr_defaultBundle;
@end

@implementation NSBundle (Msngr)

+ (NSBundle *)msngr_defaultBundle {
    static NSBundle *bundle = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *tweakBundlePath = [[NSBundle mainBundle] pathForResource:@"Flow" ofType:@"bundle"];
        if (tweakBundlePath && [[NSFileManager defaultManager] fileExistsAtPath:tweakBundlePath]) {
            bundle = [NSBundle bundleWithPath:tweakBundlePath];
            return;
        }

        NSString *defaultPath = @"/Library/Application Support/Flow.bundle";
        typedef NSString *(*jbroot_func_t)(NSString *);
        jbroot_func_t jbroot_fn = (jbroot_func_t)dlsym(RTLD_DEFAULT, "__Z6jbrootP8NSString");
        if (!jbroot_fn) {
            jbroot_fn = (jbroot_func_t)dlsym(RTLD_DEFAULT, "jbroot");
        }
        if (jbroot_fn) {
            NSString *roothidePath = jbroot_fn(defaultPath);
            if (roothidePath && [[NSFileManager defaultManager] fileExistsAtPath:roothidePath]) {
                bundle = [NSBundle bundleWithPath:roothidePath];
                return;
            }
        }

        NSArray<NSString *> *fallbackPaths = @[
            @"/var/jb/Library/Application Support/Flow.bundle",
            defaultPath
        ];
        for (NSString *candidate in fallbackPaths) {
            if ([[NSFileManager defaultManager] fileExistsAtPath:candidate]) {
                bundle = [NSBundle bundleWithPath:candidate];
                break;
            }
        }
    });
    return bundle;
}

@end

@interface MsngrUserDefaults : NSUserDefaults
+ (instancetype)standardUserDefaults;
- (void)registerDefaults;
@end

@implementation MsngrUserDefaults

+ (instancetype)standardUserDefaults {
    static MsngrUserDefaults *defaults = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        defaults = [[MsngrUserDefaults alloc] initWithSuiteName:@"twitter.nowesr1.flow"];
        [defaults registerDefaults];
    });
    return defaults;
}

- (void)registerDefaults {
    [self registerDefaults:@{
        @"noAds": @YES,
        @"antiUnsend": @YES
    }];
}

@end

static NSDictionary<NSString *, NSString *> *FlowEnglishStrings(void) {
    static NSDictionary<NSString *, NSString *> *dict = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        dict = @{
            @"Chats": @"Chats",
            @"RemoveAds": @"Remove Ads",
            @"RemoveStories": @"Remove Stories",
            @"RemovePYMK": @"Remove People You May Know",
            @"NoTypingIndicator": @"Disable Typing Indicator",
            @"ReadAnonymously": @"Read Messages Anonymously",
            @"ReadAnonymouslyDesc": @"Don't let people know when you've read their messages",
            @"AntiUnsend": @"Anti-Unsend Messages",
            @"AntiUnsendDesc": @"Keep messages and media unsent by others",
            @"SelectAction": @"Select Action",
            @"SendEmoji": @"Send Emoji",
            @"MarkMessagesAsSeen": @"Mark Messages as Seen",
            @"Stories": @"Stories",
            @"LoopStories": @"Loop Stories",
            @"StoriesAnonymously": @"View Stories Anonymously",
            @"StoriesAnonymouslyDesc": @"Don't let people know when you've seen their stories",
            @"MarkStoryAsSeen": @"Mark Story as Seen",
            @"DownloadStories": @"Download Stories",
            @"DownloadStoriesDesc": @"Save stories to library using three dots button inside story",
            @"DownloadStory": @"Download Story",
            @"Downloading": @"Downloading",
            @"SavedToPhotos": @"Saved to Photos",
            @"FailedSaveImage": @"Failed to Save Image",
            @"FailedDownloadVideo": @"Failed to Download Video",
            @"FailedSaveVideo": @"Failed to Save Video",
            @"Other": @"Other",
            @"RemoveStoriesTab": @"Remove Stories Tab",
            @"RemoveFriendsTab": @"Remove Friends Tab",
            @"NoAiCircle": @"Remove Meta AI button",
            @"CallConfirmation": @"Require Call Confirmation",
            @"AudioCall": @"Audio Call",
            @"VideoCall": @"Video Call",
            @"Cancel": @"Cancel",
            @"Developer": @"Developers",
            @"FollowMe": @"Follow %@ on Twitter",
            @"DiscordDesc": @"Join Discord Server for support & updates",
            @"GithubDesc": @"Flow's repository on GitHub",
            @"DvntmsDesc": @"All my tweaks in one place",
            @"DonateMe": @"Every donation is deeply appreciated",
            @"StoreDesc": @"Your #1 store for tweaked apps",
            @"DeveloperFooter": @"Developed by Dan & Nasser"
        };
    });
    return dict;
}

static inline NSString *LOC(NSString *key) {
    NSBundle *bundle = [NSBundle msngr_defaultBundle];
    if (bundle) {
        NSString *localized = [bundle localizedStringForKey:key value:nil table:@"Localizable"];
        if (localized && ![localized isEqualToString:key]) {
            return localized;
        }
    }
    return FlowEnglishStrings()[key] ?: key;
}

static inline UIImage *FlowBundleOrSystemImage(NSString *bundleImageName, NSString *sfSymbolFallback) {
    NSBundle *bundle = [NSBundle msngr_defaultBundle];
    if (bundle) {
        UIImage *img = [UIImage imageNamed:bundleImageName inBundle:bundle compatibleWithTraitCollection:nil];
        if (img) return img;
    }
    return [UIImage systemImageNamed:sfSymbolFallback];
}

@interface SettingsViewController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
    NSArray *_sections;
    NSArray *_chats;
    NSArray *_stories;
    NSArray *_other;
    NSArray *_dan;
    NSArray *_nwsr;
    UITableView *_tableView;
}
@property (nonatomic, strong) UITableView *tableView;
- (UIImage *)devCellImage:(NSString *)imgName;
- (void)toggleSwitch:(UISwitch *)sender;
- (void)locButtonTapped:(UIBarButtonItem *)sender;
- (void)updateInterfaceForTraitCollection:(UITraitCollection *)traitCollection;
@end

@implementation SettingsViewController

- (instancetype)init {
    if ((self = [super init])) {
        _chats = @[
            @{@"title": @"RemoveAds", @"type": @"bool", @"key": @"noAds", @"id": @"chatsCell"},
            @{@"title": @"RemoveStories", @"type": @"bool", @"key": @"noStories", @"id": @"chatsCell"},
            @{@"title": @"RemovePYMK", @"type": @"bool", @"key": @"noPYMK", @"id": @"chatsCell"},
            @{@"title": @"NoTypingIndicator", @"type": @"bool", @"key": @"noTypingIndicator", @"id": @"chatsCell"},
            @{@"title": @"ReadAnonymously", @"desc": @"ReadAnonymouslyDesc", @"type": @"bool", @"key": @"msgAnon", @"id": @"chatsCell"},
            @{@"title": @"AntiUnsend", @"desc": @"AntiUnsendDesc", @"type": @"bool", @"key": @"antiUnsend", @"id": @"chatsCell"}
        ];

        _stories = @[
            @{@"title": @"LoopStories", @"type": @"bool", @"key": @"loopStories", @"id": @"storiesCell"},
            @{@"title": @"StoriesAnonymously", @"desc": @"StoriesAnonymouslyDesc", @"type": @"bool", @"key": @"storiesAnon", @"id": @"storiesCell"},
            @{@"title": @"DownloadStories", @"desc": @"DownloadStoriesDesc", @"type": @"bool", @"key": @"downloadStories", @"id": @"storiesCell"}
        ];

        _other = @[
            @{@"title": @"RemoveStoriesTab", @"type": @"bool", @"key": @"noStoriesTab", @"id": @"mainCell"},
            @{@"title": @"RemoveFriendsTab", @"type": @"bool", @"key": @"noFriendsTab", @"id": @"mainCell"},
            @{@"title": @"NoAiCircle", @"type": @"bool", @"key": @"noAiCircle", @"id": @"mainCell"},
            @{@"title": @"CallConfirmation", @"type": @"bool", @"key": @"callConfirmation", @"id": @"mainCell"}
        ];

        _dan = @[
            @{@"title": @"Dayanch96", @"desc": @"FollowMe", @"img": @"dvn", @"type": @"link", @"key": @"https://twitter.com/dayanch96", @"id": @"devCell"},
            @{@"title": @"Discord", @"desc": @"DiscordDesc", @"img": @"dc", @"type": @"link", @"key": @"https://discord.gg/VN9ZSeMhEW", @"id": @"devCell"},
            @{@"title": @"Github", @"desc": @"GithubDesc", @"img": @"gh", @"type": @"link", @"key": @"https://github.com/dayanch96/flow", @"id": @"devCell"},
            @{@"title": @"Dan's Workshop", @"desc": @"DvntmsDesc", @"img": @"repo", @"type": @"link", @"key": @"https://dvntm0.github.io", @"id": @"devCell"}
        ];

        _nwsr = @[
            @{@"title": @"Nasser | NoTimeToChill", @"desc": @"FollowMe", @"img": @"nwsr", @"type": @"link", @"key": @"https://twitter.com/nowesr1", @"id": @"nwsrCell"},
            @{@"title": @"Ko-Fi", @"desc": @"DonateMe", @"img": @"kofi", @"type": @"link", @"key": @"https://ko-fi.com/nowesr", @"id": @"nwsrCell"},
            @{@"title": @"Nasser iPA Store", @"desc": @"StoreDesc", @"img": @"na9", @"type": @"link", @"key": @"https://na9.me", @"id": @"nwsrCell"}
        ];

        _sections = @[_chats, _stories, _other, _dan, _nwsr];
    }
    return self;
}

- (NSString *)title {
    return @"Flow";
}

- (void)viewDidLoad {
    [super viewDidLoad];
    FlowWriteLog(@"SettingsViewController viewDidLoad");

    UIImage *langIcon = [FlowBundleOrSystemImage(@"non_ar", @"globe")
                         imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];

    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:langIcon
                                                                              style:UIBarButtonItemStylePlain
                                                                             target:self
                                                                             action:@selector(locButtonTapped:)];

    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.translatesAutoresizingMaskIntoConstraints = NO;
    self.tableView.dataSource = self;
    self.tableView.delegate = self;
    self.tableView.tintColor = [UIColor colorWithRed:0.686 green:0.22 blue:0.922 alpha:1.0];
    [self.view addSubview:self.tableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.tableView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.tableView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.tableView.widthAnchor constraintEqualToAnchor:self.view.widthAnchor],
        [self.tableView.heightAnchor constraintEqualToAnchor:self.view.heightAnchor]
    ]];

    [self updateInterfaceForTraitCollection:self.traitCollection];
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    [super traitCollectionDidChange:previousTraitCollection];
    if ([self.traitCollection hasDifferentColorAppearanceComparedToTraitCollection:previousTraitCollection]) {
        [self updateInterfaceForTraitCollection:self.traitCollection];
    }
}

- (void)updateInterfaceForTraitCollection:(UITraitCollection *)traitCollection {
    [self.tableView reloadData];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return UITableViewAutomaticDimension;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    if (section == [_sections indexOfObject:_chats]) return LOC(@"Chats");
    if (section == [_sections indexOfObject:_stories]) return LOC(@"Stories");
    if (section == [_sections indexOfObject:_other]) return LOC(@"Other");
    if (section == [_sections indexOfObject:_dan]) return LOC(@"Developer");
    return nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == [_sections indexOfObject:_nwsr]) {
        NSString *appVersion = [[NSBundle mainBundle] infoDictionary][@"CFBundleShortVersionString"];
        return [NSString stringWithFormat:@"%@\n\nFlow: %@ - Messenger: %@", LOC(@"DeveloperFooter"), @"1.0.3", appVersion];
    }
    return nil;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return _sections.count;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return [_sections[section] count];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _sections[indexPath.section][indexPath.row];
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:item[@"id"]];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:item[@"id"]];
    }

    if (self.traitCollection.userInterfaceStyle == UIUserInterfaceStyleLight) {
        cell.backgroundColor = [UIColor systemBackgroundColor];
    } else {
        cell.backgroundColor = [UIColor secondarySystemBackgroundColor];
    }

    NSString *titleKey = item[@"title"];
    cell.textLabel.text = LOC(titleKey);
    cell.textLabel.adjustsFontSizeToFitWidth = YES;

    NSArray *rawTitles = @[@"Dayanch96", @"Discord", @"Github", @"Dan's Workshop", @"Nasser | NoTimeToChill", @"Ko-Fi", @"Nasser iPA Store"];
    if ([rawTitles containsObject:titleKey]) {
        cell.textLabel.text = titleKey;
    }

    NSString *descKey = item[@"desc"];
    if (descKey) {
        if ([descKey isEqualToString:@"FollowMe"]) {
            cell.detailTextLabel.text = [NSString stringWithFormat:LOC(descKey), titleKey];
        } else {
            cell.detailTextLabel.text = LOC(descKey);
        }
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.textColor = [UIColor secondaryLabelColor];
    } else {
        cell.detailTextLabel.text = nil;
    }

    if ([item[@"type"] isEqualToString:@"bool"]) {
        UISwitch *toggle = [[UISwitch alloc] init];
        [toggle addTarget:self action:@selector(toggleSwitch:) forControlEvents:UIControlEventValueChanged];
        toggle.tag = (indexPath.section << 16) | indexPath.row;
        toggle.on = [[MsngrUserDefaults standardUserDefaults] boolForKey:item[@"key"]];
        toggle.onTintColor = self.tableView.tintColor;
        cell.imageView.image = nil;
        cell.accessoryView = toggle;
    } else if ([item[@"type"] isEqualToString:@"link"]) {
        cell.imageView.image = [self devCellImage:item[@"img"]];
        cell.accessoryView = [[UIImageView alloc] initWithImage:[UIImage systemImageNamed:@"safari"]];
    }

    return cell;
}

- (UIImage *)devCellImage:(NSString *)imgName {
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(40, 40)];
    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *rendererContext) {
        UIView *containerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 40, 40)];
        UIImage *img = FlowBundleOrSystemImage(imgName, @"person.crop.circle.fill");
        UIImageView *imageView = [[UIImageView alloc] initWithImage:img];
        imageView.contentMode = UIViewContentModeScaleAspectFit;
        imageView.frame = containerView.bounds;
        imageView.clipsToBounds = YES;
        imageView.layer.cornerRadius = containerView.bounds.size.width / 2.0;
        imageView.layer.borderWidth = 1.0;
        imageView.layer.borderColor = [[UIColor whiteColor] colorWithAlphaComponent:0.3].CGColor;
        [containerView addSubview:imageView];
        [containerView.layer renderInContext:rendererContext.CGContext];
    }];
}

- (BOOL)tableView:(UITableView *)tableView shouldHighlightRowAtIndexPath:(NSIndexPath *)indexPath {
    return YES;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *item = _sections[indexPath.section][indexPath.row];
    if ([item[@"type"] isEqualToString:@"bool"]) {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        UISwitch *toggle = (UISwitch *)cell.accessoryView;
        [toggle setOn:!toggle.isOn animated:YES];
        [self toggleSwitch:toggle];
    } else if ([item[@"type"] isEqualToString:@"link"]) {
        NSURL *url = [NSURL URLWithString:item[@"key"]];
        if ([[UIApplication sharedApplication] canOpenURL:url]) {
            [[UIApplication sharedApplication] openURL:url options:@{} completionHandler:nil];
        }
    }
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)toggleSwitch:(UISwitch *)sender {
    NSInteger section = sender.tag >> 16;
    NSInteger row = sender.tag & 0xFFFF;
    NSDictionary *item = _sections[section][row];
    NSString *key = item[@"key"];
    [[MsngrUserDefaults standardUserDefaults] setBool:sender.isOn forKey:key];
    [[MsngrUserDefaults standardUserDefaults] synchronize];
    if ([key isEqualToString:@"antiUnsend"]) {
        gAntiUnsend = sender.isOn;
    }
    FlowWriteLog([NSString stringWithFormat:@"Toggled %@ = %d", key, (int)sender.isOn]);
    if (gActiveTabBar) {
        [gActiveTabBar items];
        [gActiveTabBar setNeedsLayout];
        [gActiveTabBar layoutIfNeeded];
        [gActiveTabBar layoutSubviews];
    }
}

- (void)locButtonTapped:(UIBarButtonItem *)sender {
}

@end

NSURL *fakeGroupContainerURL = nil;

void createDirectoryIfNotExists(NSURL *url) {
    if (![url checkResourceIsReachableAndReturnError:nil]) {
        [[NSFileManager defaultManager] createDirectoryAtURL:url
                                 withIntermediateDirectories:YES
                                                  attributes:nil
                                                       error:nil];
    }
}

static NSString *keychainAccessGroup(void) {
    static NSString *accessGroup = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSDictionary *query = @{
            (__bridge id)kSecClass: (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrAccount: @"dvnServiceName",
            (__bridge id)kSecAttrService: @"dvnAccountName",
            (__bridge id)kSecReturnAttributes: @YES
        };
        CFTypeRef result = NULL;
        OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
        if (status == errSecItemNotFound) {
            status = SecItemAdd((__bridge CFDictionaryRef)query, &result);
        }
        if (status == errSecSuccess && result) {
            accessGroup = [(__bridge NSDictionary *)result objectForKey:(__bridge id)kSecAttrAccessGroup];
            CFRelease(result);
        }
    });
    return accessGroup;
}

%group SideloadedFixes

%hook NSFileManager
- (NSURL *)containerURLForSecurityApplicationGroupIdentifier:(NSString *)groupIdentifier {
    NSURL *url = [fakeGroupContainerURL URLByAppendingPathComponent:groupIdentifier];
    createDirectoryIfNotExists(url);
    createDirectoryIfNotExists([url URLByAppendingPathComponent:@"Library"]);
    createDirectoryIfNotExists([url URLByAppendingPathComponent:@"Library/Caches"]);
    return url;
}
%end

%hook FBSDKKeychainStore
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook FBKeychainItemController
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook FBBaseKeychainStoreDelegate
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook UICKeyChainStore
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook LSKeychainItemController
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook LSKeychainMultiItemController
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook FXDeviceKeychainQuery
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook FXAccountKeychainQuery
- (NSString *)accessGroup { return keychainAccessGroup(); }
%end

%hook INVocabulary
- (void)setVocabularyStrings:(id)strings ofType:(NSInteger)type {}
- (void)setVocabulary:(id)vocabulary ofType:(NSInteger)type {}
- (void)_THROW_EXCEPTION_FOR_PROCESS_MISSING_ENTITLEMENT_com_apple_developer_siri {}
%end

%end

void showConfirmation(UIViewController *vc, void (^sendEmojiBlock)(void)) {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:LOC(@"SelectAction")
                                                            preferredStyle:UIAlertControllerStyleActionSheet];

    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"SendEmoji")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        if (sendEmojiBlock) sendEmojiBlock();
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"MarkMessagesAsSeen")
                                              style:UIAlertActionStyleDefault
                                            handler:^(UIAlertAction *action) {
        UIViewController *parentVC = vc.parentViewController;
        if (parentVC && class_getInstanceVariable([parentVC class], "_messageListViewController")) {
            UIViewController *msgListVC = [parentVC valueForKey:@"_messageListViewController"];
            if (msgListVC && class_getInstanceVariable([msgListVC class], "_disableReadReceipts")) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [msgListVC setValue:@NO forKey:@"_disableReadReceipts"];
                });
            }
        }
    }]];

    [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel")
                                              style:UIAlertActionStyleCancel
                                            handler:nil]];

    UIPopoverPresentationController *popover = alert.popoverPresentationController;
    if (popover && vc.view) {
        popover.sourceView = vc.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(vc.view.bounds), CGRectGetMidY(vc.view.bounds), 1, 1);
        popover.permittedArrowDirections = 0;
    }

    [vc presentViewController:alert animated:YES completion:nil];
}

static void showHUDToast(NSString *text, NSString *systemImageName) {
    UIWindow *window = [[[UIApplication sharedApplication] delegate] window];
    if (!window) return;

    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [feedback prepare];

    UIImage *icon = [UIImage systemImageNamed:systemImageName];
    UIImageView *imageView = [[UIImageView alloc] initWithImage:icon];
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    imageView.contentMode = UIViewContentModeScaleAspectFit;

    UILabel *label = [[UILabel alloc] init];
    label.text = text;
    label.textAlignment = NSTextAlignmentCenter;
    label.translatesAutoresizingMaskIntoConstraints = NO;
    label.font = [UIFont boldSystemFontOfSize:15.0];
    label.textColor = [UIColor systemBlueColor];
    label.numberOfLines = 2;

    UIView *hudView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 150.0, 150.0)];
    hudView.translatesAutoresizingMaskIntoConstraints = NO;
    hudView.backgroundColor = [UIColor clearColor];
    hudView.layer.cornerRadius = 12.0;
    hudView.clipsToBounds = YES;
    hudView.center = window.center;
    hudView.tintColor = [UIColor systemBlueColor];

    UIBlurEffect *blur = [UIBlurEffect effectWithStyle:UIBlurEffectStyleSystemChromeMaterial];
    UIVisualEffectView *blurView = [[UIVisualEffectView alloc] initWithEffect:blur];
    blurView.translatesAutoresizingMaskIntoConstraints = NO;

    [hudView addSubview:blurView];
    [hudView addSubview:imageView];
    [hudView addSubview:label];
    [window addSubview:hudView];

    [NSLayoutConstraint activateConstraints:@[
        [blurView.leadingAnchor constraintEqualToAnchor:hudView.leadingAnchor],
        [blurView.trailingAnchor constraintEqualToAnchor:hudView.trailingAnchor],
        [blurView.topAnchor constraintEqualToAnchor:hudView.topAnchor],
        [blurView.bottomAnchor constraintEqualToAnchor:hudView.bottomAnchor],
        [imageView.centerXAnchor constraintEqualToAnchor:hudView.centerXAnchor],
        [imageView.centerYAnchor constraintEqualToAnchor:hudView.centerYAnchor constant:-15.0],
        [imageView.widthAnchor constraintEqualToConstant:50.0],
        [imageView.heightAnchor constraintEqualToConstant:50.0],
        [label.topAnchor constraintEqualToAnchor:imageView.bottomAnchor constant:10.0],
        [label.leadingAnchor constraintEqualToAnchor:hudView.leadingAnchor constant:10.0],
        [label.trailingAnchor constraintEqualToAnchor:hudView.trailingAnchor constant:-10.0],
        [label.bottomAnchor constraintEqualToAnchor:hudView.bottomAnchor constant:-10.0],
        [hudView.centerXAnchor constraintEqualToAnchor:window.centerXAnchor],
        [hudView.centerYAnchor constraintEqualToAnchor:window.centerYAnchor constant:0.0],
        [hudView.widthAnchor constraintEqualToConstant:150.0],
        [hudView.heightAnchor constraintEqualToConstant:150.0]
    ]];

    hudView.alpha = 0.0;
    hudView.transform = CGAffineTransformMakeScale(1.2, 1.2);
    [feedback impactOccurred];

    [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseOut animations:^{
        hudView.alpha = 1.0;
        hudView.transform = CGAffineTransformIdentity;
    } completion:nil];

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [UIView animateWithDuration:0.3 delay:0.0 options:UIViewAnimationOptionCurveEaseIn animations:^{
            hudView.alpha = 0.0;
            hudView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        } completion:^(BOOL finished) {
            [hudView removeFromSuperview];
        }];
    });
}

%group MessengerHooks

%hook MSGThreadListDataSource

- (NSArray *)inboxRows {
    NSArray *origRows = %orig;
    NSMutableArray *rows = [origRows mutableCopy];
    NSIndexSet *indexesToRemove = [rows indexesOfObjectsPassingTest:^BOOL(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:objc_getClass("MSGInboxRowUnit")]) {
            NSString *unitKey = [[(MSGInboxRowUnit *)obj inboxUnit] key];
            if ([unitKey isEqualToString:@"ads_renderer"] && [[MsngrUserDefaults standardUserDefaults] boolForKey:@"noAds"]) {
                return YES;
            }
            if ([unitKey isEqualToString:@"montage_renderer"] && [[MsngrUserDefaults standardUserDefaults] boolForKey:@"noStories"]) {
                return YES;
            }
        }
        return NO;
    }];
    [rows removeObjectsAtIndexes:indexesToRemove];
    return [rows copy];
}

- (NSArray *)inboxPYMKUserModels {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"noPYMK"]) {
        return nil;
    }
    return %orig;
}

%end

%hook MSGHighlightsTabPeopleYouMayKnowFeedItemContentView
- (void)_setUpPymkView {
    if (![[MsngrUserDefaults standardUserDefaults] boolForKey:@"noPYMK"]) {
        %orig;
    }
}
%end

%hook UIButton
- (void)layoutSubviews {
    %orig;
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"noAiCircle"]) {
        if ([self isKindOfClass:NSClassFromString(@"MSGMetaAIFAB.MSGMetaAIFAB")]) {
            [self setAlpha:0.0];
        }
    }
}
%end

%hook LSComposerViewController

- (void)lsTextViewDidUpdateText:(UITextView *)textView isProgrammatically:(BOOL)isProgrammatically {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"noTypingIndicator"]) {
        if (class_getInstanceVariable([self class], "_sendButton") &&
            class_getInstanceVariable([self class], "_mainOtherActionButton")) {
            UIControl *sendButton = (UIControl *)[self valueForKey:@"_sendButton"];
            UIView *otherButton = [self valueForKey:@"_mainOtherActionButton"];
            BOOL hasText = textView.text.length > 0;
            [sendButton setHidden:!hasText];
            [sendButton setEnabled:hasText];
            [sendButton setAlpha:hasText ? 1.0 : 0.0];
            [otherButton setHidden:hasText];
            if ([self respondsToSelector:@selector(composerBarCollapseBehavior)]) {
                [[self composerBarCollapseBehavior] renderComposerBarForState:1];
                [[self composerBarCollapseBehavior] _updateTextViewForComposerBarState:1];
            }
        }
        return;
    }
    %orig;
}

- (void)updateComposerPlaceholderTextForExpandedState {
    if (![[MsngrUserDefaults standardUserDefaults] boolForKey:@"noTypingIndicator"]) {
        %orig;
    }
}

- (void)_didPressEmojiButton:(id)sender {
    if ([self.parentViewController isKindOfClass:objc_getClass("MSGThreadViewController")] &&
        [[MsngrUserDefaults standardUserDefaults] boolForKey:@"msgAnon"]) {
        showConfirmation(self, ^{
            %orig;
        });
    } else {
        %orig;
    }
}

- (void)_didPressOtherActionButton {
    if ([self.parentViewController isKindOfClass:objc_getClass("MSGThreadViewController")] &&
        [[MsngrUserDefaults standardUserDefaults] boolForKey:@"msgAnon"]) {
        showConfirmation(self, ^{
            %orig;
        });
    } else {
        %orig;
    }
}

%end

%hook MSGMessageListViewController
- (void)viewDidLoad {
    %orig;
    if (class_getInstanceVariable([self class], "_disableReadReceipts")) {
        BOOL msgAnon = [[MsngrUserDefaults standardUserDefaults] boolForKey:@"msgAnon"];
        [self setValue:@(msgAnon) forKey:@"_disableReadReceipts"];
    }
}
%end

%hook MSGTempMessageListItemModel
- (BOOL)isTombstoned {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"]) {
        return NO;
    }
    return %orig;
}
- (BOOL)isMediaGapTombstoned {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"]) {
        return NO;
    }
    return %orig;
}
- (BOOL)isNoteTombstoned {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"]) {
        return NO;
    }
    return %orig;
}
- (BOOL)isSpectraTombstoned {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"]) {
        return NO;
    }
    return %orig;
}
%end

%hook MSGTempMessageAttachmentListItemModel
- (BOOL)isTombstoned {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"]) {
        return NO;
    }
    return %orig;
}
%end

%hook LSStoryBucketViewController

- (void)startTimer {
    if (![[MsngrUserDefaults standardUserDefaults] boolForKey:@"storiesAnon"]) {
        %orig;
    }
}

- (void)videoDidPlayToEnd:(id)arg1 {
    if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"loopStories"]) {
        [self playFromBeginningWhenPossible];
        if (![[MsngrUserDefaults standardUserDefaults] boolForKey:@"storiesAnon"]) {
            [self didFullyDisplayBucket];
        }
    } else {
        %orig;
    }
}

%end

%hook LSMediaViewController
- (BOOL)canSaveMedia    { return YES; }
- (BOOL)canForwardMedia { return YES; }
- (BOOL)canShareMedia   { return YES; }
%end

%hook LSStoryOverlayProfileView
- (void)setActionHandler:(void (^)(UIAlertController *))actionHandler {
    %orig;
    if (class_getInstanceVariable([self class], "_actionSheetHandler")) {
        void (^origHandler)(UIAlertController *) = [self valueForKey:@"_actionSheetHandler"];
        void (^newHandler)(UIAlertController *) = ^(UIAlertController *alert) {
            if (origHandler) {
                origHandler(alert);
            }
            if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"storiesAnon"]) {
                [alert addAction:[UIAlertAction actionWithTitle:LOC(@"MarkStoryAsSeen")
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                    UIViewController *vc = [[self _viewControllerForAncestor] parentViewController];
                    if ([vc isKindOfClass:objc_getClass("LSStoryBucketViewController")]) {
                        [(LSStoryBucketViewController *)vc didFullyDisplayBucket];
                        [(LSStoryBucketViewController *)vc startTimer];
                    }
                }]];
            }
            if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"downloadStories"]) {
                [alert addAction:[UIAlertAction actionWithTitle:LOC(@"DownloadStory")
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                    UIViewController *vc = [[self _viewControllerForAncestor] parentViewController];
                    if ([vc isKindOfClass:objc_getClass("LSStoryBucketViewController")]) {
                        if (class_getInstanceVariable([vc class], "_currentThreadVC")) {
                            id threadVC = [vc valueForKey:@"_currentThreadVC"];
                            if (class_getInstanceVariable([threadVC class], "_mediaContentVC")) {
                                id mediaContentVC = [threadVC valueForKey:@"_mediaContentVC"];
                                if (class_getInstanceVariable([mediaContentVC class], "_mediaList")) {
                                    LSMediaItem *mediaList = [mediaContentVC valueForKey:@"_mediaList"];
                                    NSURL *url = [NSURL URLWithString:[mediaList mediaUrl]];
                                    showHUDToast(LOC(@"Downloading"), @"arrow.down.circle");
                                    [[[NSURLSession sharedSession] downloadTaskWithURL:url
                                                                     completionHandler:^(NSURL *location, NSURLResponse *response, NSError *error) {
                                        if (error || !location) {
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                showHUDToast(LOC(@"FailedDownloadVideo"), @"xmark");
                                            });
                                            return;
                                        }
                                        NSInteger mType = [mediaList mediaType];
                                        if (mType == 2) {
                                            NSData *data = [NSData dataWithContentsOfURL:location];
                                            UIImage *image = [UIImage imageWithData:data];
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                if (image) {
                                                    UIImageWriteToSavedPhotosAlbum(image, nil, nil, NULL);
                                                    showHUDToast(LOC(@"SavedToPhotos"), @"checkmark");
                                                } else {
                                                    showHUDToast(LOC(@"FailedSaveImage"), @"xmark");
                                                }
                                            });
                                        } else if (mType == 4) {
                                            NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:[url lastPathComponent]];
                                            NSURL *tempURL = [NSURL fileURLWithPath:tempPath];
                                            [[NSFileManager defaultManager] removeItemAtURL:tempURL error:nil];
                                            NSError *moveErr = nil;
                                            [[NSFileManager defaultManager] moveItemAtURL:location toURL:tempURL error:&moveErr];
                                            dispatch_async(dispatch_get_main_queue(), ^{
                                                if (!moveErr) {
                                                    UISaveVideoAtPathToSavedPhotosAlbum(tempPath, nil, nil, NULL);
                                                    showHUDToast(LOC(@"SavedToPhotos"), @"checkmark");
                                                } else {
                                                    showHUDToast(LOC(@"FailedSaveVideo"), @"xmark");
                                                }
                                            });
                                        }
                                    }] resume];
                                }
                            }
                        }
                    }
                }]];
            }
        };
        [self setValue:newHandler forKey:@"_actionSheetHandler"];
    }
}
%end

%hook UITabBar
- (NSArray *)items {
    gActiveTabBar = self;
    NSArray *origItems = %orig;
    NSMutableArray *items = [origItems mutableCopy];
    NSIndexSet *indexesToRemove = [items indexesOfObjectsPassingTest:^BOOL(MDSTabBarItem *item, NSUInteger idx, BOOL *stop) {
        BOOL shouldHide = NO;
        if ([item respondsToSelector:@selector(props)]) {
            NSString *ident = [[item props] accessibilityIdentifierText];
            if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"noStoriesTab"] &&
                [ident isEqualToString:@"tabbar-stories"]) {
                shouldHide = YES;
            }
            if ([[MsngrUserDefaults standardUserDefaults] boolForKey:@"noFriendsTab"] &&
                [ident isEqualToString:@"tabbar-highlights"]) {
                shouldHide = YES;
            }
        }
        [[item view] setHidden:shouldHide];
        return shouldHide;
    }];
    [items removeObjectsAtIndexes:indexesToRemove];
    return [items copy];
}
%end

%hook LSTargetAction
- (void)handle:(id)sender {
    if (class_getInstanceVariable([self class], "_context") &&
        [[MsngrUserDefaults standardUserDefaults] boolForKey:@"callConfirmation"]) {
        UIView *context = [self valueForKey:@"_context"];
        if ([context isKindOfClass:[UIView class]] && context.subviews.count > 0) {
            UIView *firstSub = context.subviews[0];
            if ([firstSub.superview.description containsString:@"RTCCallButton"]) {
                BOOL isVoiceCall = [firstSub.accessibilityIdentifier isEqualToString:@"rtc-voice-call-button"];
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil
                                                                               message:nil
                                                                        preferredStyle:UIAlertControllerStyleActionSheet];
                [alert addAction:[UIAlertAction actionWithTitle:LOC(isVoiceCall ? @"AudioCall" : @"VideoCall")
                                                          style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction *action) {
                    %orig;
                }]];
                [alert addAction:[UIAlertAction actionWithTitle:LOC(@"Cancel")
                                                          style:UIAlertActionStyleCancel
                                                        handler:nil]];
                UIViewController *ancestorVC = [context _viewControllerForAncestor];
                UIPopoverPresentationController *popover = alert.popoverPresentationController;
                if (popover) {
                    popover.sourceView = context;
                    popover.sourceRect = context.bounds;
                }
                [ancestorVC presentViewController:alert animated:YES completion:nil];
                return;
            }
        }
    }
    %orig;
}
%end

%hook MSGSettingsViewController
- (void)viewDidLoad {
    %orig;
    UIImage *icon = [FlowBundleOrSystemImage(@"icon", @"gearshape.fill")
                     imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIBarButtonItem *flowItem = [[UIBarButtonItem alloc] initWithImage:icon
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(msngrButtonTapped:)];
    if (self.navigationItem.leftBarButtonItem.action == @selector(_handleQRCodeLeftNavigationTap:)) {
        self.navigationItem.rightBarButtonItem = flowItem;
    } else {
        self.navigationItem.leftBarButtonItem = flowItem;
    }
}

%new
- (void)msngrButtonTapped:(id)sender {
    FlowWriteLog(@"Opening SettingsViewController");
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}
%end

%hook MSGCommunityListViewController
- (void)viewDidLoad {
    %orig;
    UIImage *icon = [FlowBundleOrSystemImage(@"icon", @"gearshape.fill")
                     imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    UIBarButtonItem *flowItem = [[UIBarButtonItem alloc] initWithImage:icon
                                                                 style:UIBarButtonItemStylePlain
                                                                target:self
                                                                action:@selector(msngrButtonTapped:)];
    self.navigationItem.rightBarButtonItem = flowItem;
}

%new
- (void)msngrButtonTapped:(id)sender {
    FlowWriteLog(@"Opening SettingsViewController");
    SettingsViewController *vc = [[SettingsViewController alloc] init];
    [self.navigationController pushViewController:vc animated:YES];
}
%end

%end

%ctor {
    @autoreleasepool {
        FlowInstallCrashHandlers();
        gAntiUnsend = [[MsngrUserDefaults standardUserDefaults] boolForKey:@"antiUnsend"];
        FlowInstallSqliteAntiUnsendHook();

        NSDictionary *entitlements = [(LSApplicationProxy *)[objc_getClass("LSApplicationProxy") bundleProxyForCurrentProcess] entitlements];
        BOOL isOfficialSigning = [entitlements[@"application-identifier"] isEqualToString:@"T84QZS65DQ.com.facebook.Messenger"];
        BOOL isOfficialBundleID = [[[NSBundle mainBundle] infoDictionary][@"CFBundleIdentifier"] isEqualToString:@"com.facebook.Messenger"];

        NSMutableArray *injectedDylibs = [NSMutableArray array];
        NSArray *bundleContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:[[NSBundle mainBundle] bundlePath] error:nil];
        for (NSString *file in bundleContents) {
            if ([file hasSuffix:@".dylib"]) {
                [injectedDylibs addObject:file];
            }
        }
        NSString *frameworksPath = [[NSBundle mainBundle] privateFrameworksPath];
        if ([[NSFileManager defaultManager] fileExistsAtPath:frameworksPath]) {
            NSArray *fwContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:frameworksPath error:nil];
            for (NSString *file in fwContents) {
                if ([file hasSuffix:@".dylib"]) {
                    [injectedDylibs addObject:file];
                }
            }
        }
        for (uint32_t i = 0; i < _dyld_image_count(); i++) {
            NSString *imageName = [[NSString stringWithUTF8String:_dyld_get_image_name(i)] lastPathComponent];
            if ([imageName isEqualToString:@"Flow.dylib"]) {
                [injectedDylibs addObject:imageName];
            }
        }

        if (!isOfficialSigning || !isOfficialBundleID || injectedDylibs.count > 0) {
            NSString *fakeContainersPath = [NSHomeDirectory() stringByAppendingPathComponent:@"Documents/FakeGroupContainers"];
            fakeGroupContainerURL = [NSURL fileURLWithPath:fakeContainersPath isDirectory:YES];
            %init(SideloadedFixes);
        }

        %init(MessengerHooks);
    }
}
