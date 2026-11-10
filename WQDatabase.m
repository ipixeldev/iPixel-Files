#import "WQDatabase.h"
#import "WQAccess.h"
#import "WQUI.h"
#import "IPTheme.h"
#import <sqlite3.h>

static NSString *wqd_text(sqlite3_stmt *statement, int column)
{
    if (sqlite3_column_type(statement, column) == SQLITE_NULL) return @"NULL";
    if (sqlite3_column_type(statement, column) == SQLITE_BLOB)
        return [NSString stringWithFormat:@"<%d-byte blob>", sqlite3_column_bytes(statement, column)];
    const unsigned char *text = sqlite3_column_text(statement, column);
    if (!text) return @"";
    return [NSString stringWithUTF8String:(const char *)text] ?: @"<invalid UTF-8>";
}

static sqlite3 *wqd_open(NSString *path, NSString **errorText)
{
    (void)wq_grant(path.stringByDeletingLastPathComponent);
    (void)wq_grant(path);
    sqlite3 *database = NULL;
    int result = sqlite3_open_v2(path.fileSystemRepresentation, &database,
                                 SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, NULL);
    if (result != SQLITE_OK) {
        if (errorText) *errorText = database ? [NSString stringWithUTF8String:sqlite3_errmsg(database)] : @"Cannot open database.";
        if (database) sqlite3_close(database);
        return NULL;
    }
    sqlite3_busy_timeout(database, 1500);
    return database;
}

@interface WQDatabaseRowsViewController : UIViewController
- (instancetype)initWithPath:(NSString *)path table:(NSString *)table;
@end

@implementation WQDatabaseRowsViewController {
    NSString *_path;
    NSString *_table;
    UITextView *_text;
}

- (instancetype)initWithPath:(NSString *)path table:(NSString *)table
{
    if ((self = [super init])) { _path = path.copy; _table = table.copy; self.title = table; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.view.backgroundColor = IPBackground();
    _text = [UITextView new];
    _text.translatesAutoresizingMaskIntoConstraints = NO;
    _text.editable = NO;
    _text.font = [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular];
    _text.backgroundColor = IPBackground();
    _text.textColor = IPPrimaryText();
    _text.text = @"Loading rows…";
    [self.view addSubview:_text];
    [NSLayoutConstraint activateConstraints:@[
        [_text.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [_text.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [_text.leadingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.leadingAnchor],
        [_text.trailingAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.trailingAnchor],
    ]];
    NSString *path = _path, *table = _table;
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        sqlite3 *database = wqd_open(path, &error);
        NSMutableString *output = [NSMutableString new];
        if (database) {
            NSString *quoted = [table stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""];
            NSString *sql = [NSString stringWithFormat:@"SELECT * FROM \"%@\" LIMIT 200", quoted];
            sqlite3_stmt *statement = NULL;
            if (sqlite3_prepare_v2(database, sql.UTF8String, -1, &statement, NULL) == SQLITE_OK) {
                int columns = sqlite3_column_count(statement);
                for (int i = 0; i < columns; i++) {
                    const char *columnName = sqlite3_column_name(statement, i);
                    [output appendFormat:@"%@%@", i ? @"  │  " : @"",
                        columnName ? [NSString stringWithUTF8String:columnName] : @"column"];
                }
                [output appendString:@"\n"];
                NSUInteger rows = 0;
                while (sqlite3_step(statement) == SQLITE_ROW) {
                    for (int i = 0; i < columns; i++) {
                        NSString *value = [wqd_text(statement, i) stringByReplacingOccurrencesOfString:@"\n" withString:@" ↵ "];
                        if (value.length > 160) value = [[value substringToIndex:160] stringByAppendingString:@"…"];
                        [output appendFormat:@"%@%@", i ? @"  │  " : @"", value];
                    }
                    [output appendString:@"\n"];
                    rows++;
                }
                if (rows == 0) [output appendString:@"\nThis table is empty."];
                else if (rows == 200) [output appendString:@"\nShowing the first 200 rows."];
            } else error = [NSString stringWithUTF8String:sqlite3_errmsg(database)];
            if (statement) sqlite3_finalize(statement);
            sqlite3_close(database);
        }
        dispatch_async(dispatch_get_main_queue(), ^{ self->_text.text = database || output.length ? output : (error ?: @"Cannot read table."); });
    });
}
@end

@implementation WQDatabaseViewController {
    NSString *_path;
    NSArray<NSDictionary *> *_objects;
    NSString *_error;
    BOOL _loading;
}

- (instancetype)initWithPath:(NSString *)path
{
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) { _path = path.copy; self.title = path.lastPathComponent; }
    return self;
}

- (void)viewDidLoad
{
    [super viewDidLoad];
    self.tableView.backgroundColor = IPBackground();
    _loading = YES;
    [self loadSchema];
}

- (void)loadSchema
{
    NSString *path = _path;
    dispatch_async(wq_io(), ^{
        NSString *error = nil;
        sqlite3 *database = wqd_open(path, &error);
        NSMutableArray *objects = [NSMutableArray new];
        if (database) {
            sqlite3_stmt *statement = NULL;
            const char *sql = "SELECT type,name,COALESCE(sql,'') FROM sqlite_master WHERE type IN ('table','view') AND name NOT LIKE 'sqlite_%' ORDER BY type,name";
            if (sqlite3_prepare_v2(database, sql, -1, &statement, NULL) == SQLITE_OK)
                while (sqlite3_step(statement) == SQLITE_ROW)
                    [objects addObject:@{@"type": wqd_text(statement, 0), @"name": wqd_text(statement, 1), @"sql": wqd_text(statement, 2)}];
            else error = [NSString stringWithUTF8String:sqlite3_errmsg(database)];
            if (statement) sqlite3_finalize(statement);
            sqlite3_close(database);
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_loading = NO; self->_objects = objects; self->_error = error; [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section
{
    return MAX((NSInteger)1, (NSInteger)_objects.count);
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:@"db"]
        ?: [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:@"db"];
    UIListContentConfiguration *content = cell.defaultContentConfiguration;
    if (_loading || !_objects.count) {
        content.text = _loading ? @"Reading database…" : (_error ? @"Cannot open database" : @"No tables or views");
        content.secondaryText = _error;
        content.image = [UIImage systemImageNamed:_error ? @"exclamationmark.triangle" : @"cylinder"];
        cell.accessoryType = UITableViewCellAccessoryNone;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else {
        NSDictionary *object = _objects[(NSUInteger)indexPath.row];
        content.text = object[@"name"];
        content.secondaryText = [object[@"type"] uppercaseString];
        content.image = [UIImage systemImageNamed:[object[@"type"] isEqualToString:@"view"] ? @"eye" : @"tablecells"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.selectionStyle = UITableViewCellSelectionStyleDefault;
    }
    content.textProperties.color = IPPrimaryText();
    content.secondaryTextProperties.color = IPSecondaryText();
    content.imageProperties.tintColor = IPAccent();
    cell.contentConfiguration = content;
    IPStyleCell(cell);
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if ((NSUInteger)indexPath.row >= _objects.count) return;
    NSString *name = _objects[(NSUInteger)indexPath.row][@"name"];
    [self.navigationController pushViewController:[[WQDatabaseRowsViewController alloc] initWithPath:_path table:name] animated:YES];
}
@end
