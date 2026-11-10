#import "WQArchive.h"
#import "WQAccess.h"
#import <sys/stat.h>
#import <fcntl.h>
#import <unistd.h>

typedef long long la_int64_t;
struct archive;
struct archive_entry;
extern struct archive *archive_read_new(void);
extern int archive_read_support_filter_all(struct archive *);
extern int archive_read_support_format_all(struct archive *);
extern int archive_read_open_filename(struct archive *, const char *, size_t);
extern int archive_read_next_header(struct archive *, struct archive_entry **);
extern la_int64_t archive_entry_size(struct archive_entry *);
extern const char *archive_entry_pathname_utf8(struct archive_entry *);
extern mode_t archive_entry_filetype(struct archive_entry *);
extern ssize_t archive_read_data(struct archive *, void *, size_t);
extern int archive_read_data_skip(struct archive *);
extern const char *archive_error_string(struct archive *);
extern int archive_read_free(struct archive *);

enum { WQArchiveOK = 0, WQArchiveEOF = 1 };
static const NSUInteger WQArchiveMaxEntries = 10000;
static const unsigned long long WQArchiveMaxEntryBytes = 128ull * 1024ull * 1024ull;
static const unsigned long long WQArchiveMaxTotalBytes = 512ull * 1024ull * 1024ull;

static NSString *wqa_error(struct archive *archive, NSString *fallback)
{
    const char *message = archive ? archive_error_string(archive) : NULL;
    return message ? [NSString stringWithUTF8String:message] : fallback;
}

static NSString *wqa_safe_path(struct archive_entry *entry)
{
    const char *raw = archive_entry_pathname_utf8(entry);
    if (!raw) return nil;
    NSString *path = [NSString stringWithUTF8String:raw];
    if (!path.length || [path hasPrefix:@"/"] || [path containsString:@"\0"]) return nil;
    while ([path hasSuffix:@"/"]) path = [path substringToIndex:path.length - 1];
    if (!path.length) return nil;
    for (NSString *part in [path componentsSeparatedByString:@"/"])
        if ([part isEqualToString:@".."] || [part isEqualToString:@"."] || !part.length) return nil;
    return path;
}

static struct archive *wqa_open(NSString *path, NSString **errorText)
{
    (void)wq_grant(path.stringByDeletingLastPathComponent);
    (void)wq_grant(path);
    struct archive *archive = archive_read_new();
    if (!archive) { if (errorText) *errorText = @"Could not create the archive reader."; return NULL; }
    archive_read_support_filter_all(archive);
    archive_read_support_format_all(archive);
    if (archive_read_open_filename(archive, path.fileSystemRepresentation, 64 * 1024) != WQArchiveOK) {
        if (errorText) *errorText = wqa_error(archive, @"Could not open this archive.");
        archive_read_free(archive);
        return NULL;
    }
    return archive;
}

NSArray<NSDictionary<NSString *, id> *> *WQArchiveList(NSString *path, NSString **errorText)
{
    struct archive *archive = wqa_open(path, errorText);
    if (!archive) return nil;
    NSMutableArray *items = [NSMutableArray new];
    struct archive_entry *entry = NULL;
    int result = WQArchiveOK;
    while ((result = archive_read_next_header(archive, &entry)) == WQArchiveOK) {
        if (items.count >= WQArchiveMaxEntries) { if (errorText) *errorText = @"The archive contains too many entries."; items = nil; break; }
        NSString *name = wqa_safe_path(entry);
        mode_t type = archive_entry_filetype(entry);
        if (!name || (type != S_IFREG && type != S_IFDIR)) {
            if (errorText) *errorText = @"The archive contains an unsafe path or unsupported link.";
            items = nil; break;
        }
        la_int64_t size = archive_entry_size(entry);
        [items addObject:@{@"name": name, @"size": @(MAX((la_int64_t)0, size)), @"directory": @(type == S_IFDIR)}];
        archive_read_data_skip(archive);
    }
    if (items && result != WQArchiveEOF) {
        if (errorText) *errorText = wqa_error(archive, @"The archive could not be read completely.");
        items = nil;
    }
    archive_read_free(archive);
    return items;
}

static BOOL wqa_make_parents(NSString *root, NSString *relative, NSString **errorText)
{
    NSString *parent = relative.stringByDeletingLastPathComponent;
    if (!parent.length || [parent isEqualToString:@"."]) return YES;
    NSString *cursor = root;
    for (NSString *part in [parent componentsSeparatedByString:@"/"]) {
        cursor = [cursor stringByAppendingPathComponent:part];
        struct stat st;
        if (wq_stat(cursor, &st)) {
            if (!S_ISDIR(st.st_mode)) { if (errorText) *errorText = @"An archive folder conflicts with a file."; return NO; }
        } else if (!wq_create_dir(cursor, errorText)) return NO;
    }
    return YES;
}

BOOL WQArchiveExtract(NSString *path, NSString *destination, NSString **errorText)
{
    struct stat existing;
    if (wq_stat(destination, &existing)) { if (errorText) *errorText = @"The extraction folder already exists."; return NO; }
    struct archive *archive = wqa_open(path, errorText);
    if (!archive) return NO;
    BOOL ok = wq_create_dir(destination, errorText);
    NSUInteger count = 0;
    unsigned long long total = 0;
    struct archive_entry *entry = NULL;
    int result = WQArchiveOK;
    while (ok && (result = archive_read_next_header(archive, &entry)) == WQArchiveOK) {
        if (++count > WQArchiveMaxEntries) { if (errorText) *errorText = @"The archive contains too many entries."; ok = NO; break; }
        NSString *relative = wqa_safe_path(entry);
        mode_t type = archive_entry_filetype(entry);
        la_int64_t declared = archive_entry_size(entry);
        if (!relative || (type != S_IFREG && type != S_IFDIR) || declared < 0 ||
            (unsigned long long)declared > WQArchiveMaxEntryBytes || total + (unsigned long long)declared > WQArchiveMaxTotalBytes) {
            if (errorText) *errorText = @"Unsafe entry, link, or extraction size limit exceeded.";
            ok = NO; break;
        }
        NSString *target = [destination stringByAppendingPathComponent:relative];
        if (type == S_IFDIR) {
            if (!wqa_make_parents(destination, relative, errorText)) { ok = NO; break; }
            if (!wq_create_dir(target, errorText)) { struct stat st; ok = wq_stat(target, &st) && S_ISDIR(st.st_mode); }
            continue;
        }
        if (!wqa_make_parents(destination, relative, errorText)) { ok = NO; break; }
        NSString *temporary = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        int fd = open(temporary.fileSystemRepresentation, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0600);
        if (fd < 0) { if (errorText) *errorText = @"Could not create a temporary extraction file."; ok = NO; break; }
        unsigned long long written = 0;
        uint8_t buffer[64 * 1024];
        ssize_t amount;
        while ((amount = archive_read_data(archive, buffer, sizeof(buffer))) > 0) {
            written += (unsigned long long)amount;
            if (written > WQArchiveMaxEntryBytes || total + written > WQArchiveMaxTotalBytes) { ok = NO; break; }
            ssize_t done = 0;
            while (done < amount) { ssize_t n = write(fd, buffer + done, (size_t)(amount - done)); if (n <= 0) { ok = NO; break; } done += n; }
            if (!ok) break;
        }
        if (amount < 0) ok = NO;
        if (close(fd) != 0) ok = NO;
        if (ok) ok = wq_create_file_from(target, temporary, errorText);
        [NSFileManager.defaultManager removeItemAtPath:temporary error:nil];
        if (!ok && errorText && !*errorText) *errorText = wqa_error(archive, @"Could not extract an archive entry.");
        total += written;
    }
    if (ok && result != WQArchiveEOF) { if (errorText) *errorText = wqa_error(archive, @"The archive ended unexpectedly."); ok = NO; }
    archive_read_free(archive);
    return ok;
}
