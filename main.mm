#import <Foundation/Foundation.h>
#import <CommonCrypto/CommonDigest.h>

#import "../Utils/FilePatch.h"


#define NWLog(...)		system([[NSString stringWithFormat:@"echo \"%@\"", [NSString stringWithFormat:__VA_ARGS__]] UTF8String])

//#define NO_SND_HASH				"8529117d81006a3095453fc4d7ee0f3924bd8913"
//#define DEFAULT_KO_SND_HASH		"384b005525299d4d7c48242e35ed9e6ba5a66c76"


int main(int argc, char **argv, char **envp) {
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];

	BOOL successFlag = NO;
	NSFileManager *FileManager = [NSFileManager defaultManager];

	//{{{
	NWLog(@"get muted sound file hash");

	NSData *data = [FileManager contentsAtPath:@"/Library/Application Support/CallRecorderPatch/warning.caf"];
	uint8_t digest[CC_SHA1_DIGEST_LENGTH];
	CC_SHA1(data.bytes, data.length, digest);
	NSMutableString *mutedHash = [NSMutableString stringWithCapacity:CC_SHA1_DIGEST_LENGTH * 2];
	for (int i = 0;i < CC_SHA1_DIGEST_LENGTH;i++) {
		[mutedHash appendFormat:@"%02x", digest[i]];
	}

	NWLog(@"muted sound file hash(sha1) is (%@)", mutedHash);
	//}}}

	//{{{
	NWLog(@"binary backup process 1");

	if ([FileManager fileExistsAtPath:@"/Library/MobileSubstrate/DynamicLibraries/callrecorder.dylib"] == NO) {
		NWLog(@"callrecorder.dylib file is not exist");
		successFlag = NO;
	} else {
		NSString *currentDir = [FileManager currentDirectoryPath];

		successFlag = [FileManager changeCurrentDirectoryPath:@"/Library/MobileSubstrate/DynamicLibraries"];
		successFlag = successFlag && [FileManager copyItemAtPath:@"callrecorder.dylib" toPath:@"/Library/Application Support/CallRecorderPatch/callrecorder.dylib.tmp.bak" error:nil];

		[FileManager changeCurrentDirectoryPath:currentDir];
	}

	NWLog(@"binary backup process 1 %@", (successFlag ? @"OK" : @"Fail"));

	if (!successFlag) {
		[pool drain];
		return 1;
	}
	//}}}

	//{{{
	BOOL alreadyPatched = NO;
	//NSString *locale = [[[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"] objectAtIndex:0];
	//if (locale == nil || locale.length == 0)
	//	locale = @"ko";
	NSArray *locales = [NSArray arrayWithObjects:@"ko", @"en", @"ja", nil];
	//NSString *locale = [locales objectAtIndex:0];
	for (NSString *locale in locales) {
		NWLog(@"%@ locale patch process=====================", locale);

		NSString *bundlePath = [[NSString alloc] initWithFormat:@"/Library/PreferenceBundles/CallRecorderPreferences.bundle/%@.lproj", locale];
		NSBundle *CallRecorderPrefBundle = [[NSBundle alloc] initWithPath:bundlePath];

		if (CallRecorderPrefBundle == nil) {
			NWLog(@"can not find %@ locale", locale);
			[bundlePath release];
			continue;
		}

		NSString *localeHash = [CallRecorderPrefBundle localizedStringForKey:@"LANGUAGEID" value:@"" table:@"Localizable"];
		[CallRecorderPrefBundle release];
		NWLog(@"%@ locale's original warning file hash is (%@)", locale, localeHash);

		if ([localeHash isEqualToString:mutedHash]) {
			// already patched
			NWLog(@"already patched, pass %@ locale", locale);
			alreadyPatched = YES;
		}
		else {
			NWLog(@"first process:: %@ locale backup", locale);

			NSString *warningFilePath = [NSString stringWithFormat:@"%@/warning.caf", bundlePath];
			if ([FileManager fileExistsAtPath:warningFilePath] == NO) {
				NWLog(@"warning.caf file is not exist");
				successFlag = NO;
			} else {
				NSString *currentDir = [FileManager currentDirectoryPath];

				successFlag = [FileManager changeCurrentDirectoryPath:bundlePath];
				NSString *backupPath = [NSString stringWithFormat:@"/Library/Application Support/CallRecorderPatch/%@.warning.caf.bak", locale];
				successFlag = successFlag && [FileManager moveItemAtPath:@"warning.caf" toPath:backupPath error:nil];
				backupPath = [NSString stringWithFormat:@"/Library/Application Support/CallRecorderPatch/%@.Localizable.strings.bak", locale];
				successFlag = successFlag && [FileManager copyItemAtPath:@"Localizable.strings" toPath:backupPath error:nil];
				successFlag = successFlag && [FileManager copyItemAtPath:@"/Library/Application Support/CallRecorderPatch/warning.caf" toPath:@"warning.caf" error:nil];

				[FileManager changeCurrentDirectoryPath:currentDir];
			}

			NWLog(@"first process:: %@ locale backup %@", locale, (successFlag ? @"OK" : @"Fail"));

			MPatchInfo hi;
			char abyData[41] = "";
			char abyEdit[41] = "";

			memset(abyData, 0, 41);
			memcpy(abyData, [localeHash UTF8String], 40);
			memset(abyEdit, 0, 41);
			memcpy(abyEdit, [mutedHash UTF8String], 40);

			hi.abyOrigData = abyData;
			hi.origLen = 40;
			hi.dest = 0;
			hi.abyModfData = abyEdit;
			hi.modfLen = 40;
			hi.start = 0x00000000;
			hi.end = 0x00090000;
			hi.hAddr = 0;

			if (successFlag) {
				NWLog(@"second process:: %@ locale patch", locale);

				NSString *stringFilePath = [NSString stringWithFormat:@"%@/Localizable.strings", bundlePath];
				FILE *stringFile = NULL;

				NSString *plutilCmd = [NSString stringWithFormat:@"plutil -convert xml1 %@", stringFilePath];
				system([plutilCmd UTF8String]);

				stringFile = fopen([stringFilePath UTF8String], "r+w");
				if (stringFile == NULL) {
					NWLog(@"fail to open string file");
					successFlag = NO;
				} else {
					int rtn = doMPatch(&hi, stringFile);

					if (rtn == SUCCESS_PATCH) {
						successFlag = YES;
					} else if (rtn == NOT_FOUND_PATCH_POS) {
						NWLog(@"not found patch position");
						successFlag = NO;
					} else if (rtn == CAN_NOT_PATCH_FILE) {
						NWLog(@"can not patch file");
						successFlag = NO;
					} else {
						NWLog(@"unknown error");
						successFlag = NO;
					}

					fclose(stringFile);
					stringFile = NULL;

					if (successFlag) NWLog(@"second process complete");
				}
			}

			hi.start = 0x00000000;
			hi.end = 0x00090000;
			hi.hAddr = 0;

			if (successFlag) {
				NWLog(@"third process:: binary patch");

				FILE *binaryFile = NULL;

				binaryFile = fopen("/Library/MobileSubstrate/DynamicLibraries/callrecorder.dylib", "r+w");
				if (binaryFile) {
					int patchedCount = 0;
					
					int rtn = 0;
					while (hi.start < hi.end) {
						rtn = doMPatch(&hi, binaryFile);
						
						if (rtn == SUCCESS_PATCH) {
							patchedCount++;
							NWLog(@"patched! (%d)", patchedCount);
						}
						
						if (rtn != SUCCESS_PATCH) break;
						hi.start = hi.hAddr;
						hi.hAddr = 0;
					}
					
					if (patchedCount > 1) {
						successFlag = YES;
					}
					else {
						if (rtn == NOT_FOUND_PATCH_POS) {
							NWLog(@"not found patch position : patched (%d)", patchedCount);
							successFlag = NO;
						} else if (rtn == CAN_NOT_PATCH_FILE) {
							NWLog(@"can not patch file : patched (%d)", patchedCount);
							successFlag = NO;
						} else {
							NWLog(@"unknown error : patched (%d)", patchedCount);
							successFlag = NO;
						}
					}

					fclose(binaryFile);
					binaryFile = NULL;

					if (successFlag) NWLog(@"third process complete");
				} else {
					NWLog(@"fail to open binary file");
					successFlag = NO;
				}
			}

			if (successFlag) NWLog(@"%@ locale processes complete", locale);
		}

		[bundlePath release];
	}
	//}}}

	//{{{
	NWLog(@"binary backup process 2");

	if (!alreadyPatched) {
		if ([FileManager fileExistsAtPath:@"/Library/Application Support/CallRecorderPatch/callrecorder.dylib.tmp.bak"] == NO) {
			NWLog(@"callrecorder.dylib.tmp.bak file is not exist");
			successFlag = NO;
		} else {
			NSString *currentDir = [FileManager currentDirectoryPath];

			successFlag = [FileManager changeCurrentDirectoryPath:@"/Library/Application Support/CallRecorderPatch"];
			successFlag = successFlag && [FileManager moveItemAtPath:@"callrecorder.dylib.tmp.bak" toPath:@"callrecorder.dylib.bak" error:nil];

			[FileManager changeCurrentDirectoryPath:currentDir];
		}
	} else {
		NWLog(@"but already patched. pass this process.");

		if ([FileManager fileExistsAtPath:@"/Library/Application Support/CallRecorderPatch/callrecorder.dylib.tmp.bak"]) {
			NSString *currentDir = [FileManager currentDirectoryPath];

			successFlag = [FileManager changeCurrentDirectoryPath:@"/Library/Application Support/CallRecorderPatch"];
			successFlag = successFlag && [FileManager removeItemAtPath:@"callrecorder.dylib.tmp.bak" error:nil];

			[FileManager changeCurrentDirectoryPath:currentDir];
		}
	}

	NWLog(@"binary backup process 2 %@", (successFlag ? @"OK" : @"Fail"));
	//}}}

	if (successFlag) NWLog(@"all processes complete");
	else {
		[pool drain];
		return 1;
	}

	//{{{
	system("launchctl unload /System/Library/LaunchDaemons/com.apple.mediaserverd.plist");
	system("launchctl load /System/Library/LaunchDaemons/com.apple.mediaserverd.plist");
	//}}}

	[pool drain];

	return 0;
}


// vim:ft=objc
