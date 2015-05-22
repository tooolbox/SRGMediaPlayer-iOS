//
//  Copyright (c) RTS. All rights reserved.
//
//  Licence information is available from the LICENCE file.
//

#import "SwissTXTDataSource.h"

#import "Event.h"

@implementation SwissTXTDataSource

#pragma mark - RTSMediaPlayerControllerDataSource protocol

- (void) mediaPlayerController:(RTSMediaPlayerController *)mediaPlayerController contentURLForIdentifier:(NSString *)identifier completionHandler:(void (^)(NSURL *, NSError *))completionHandler
{
	NSString *URLString = [NSString stringWithFormat:@"http://test.event.api.swisstxt.ch:80/v1/stream/srf/byEventItemIdAndType/%@/hls", identifier];
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
		if (error)
		{
			completionHandler(nil, error);
			return;
		}
		
		NSString *responseString = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
		if (! responseString)
		{
			NSError *responseError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadServerResponse userInfo:nil];
			completionHandler(nil, responseError);
		}
		responseString = [responseString stringByReplacingOccurrencesOfString:@"\"" withString:@""];
		
		NSURL *URL = [NSURL URLWithString:responseString];
		completionHandler(URL, nil);
	}];
}

#pragma mark - RTSMediaPlayerSegmentDataSource protocol

- (void) segmentDisplayer:(id<RTSMediaPlayerSegmentDisplayer>)segmentDisplayer segmentsForIdentifier:(NSString *)identifier completionHandler:(void (^)(NSArray *, NSError *))completionHandler
{
	NSString *URLString = [NSString stringWithFormat:@"http://test.event.api.swisstxt.ch:80/v1/highlights/srf/byEventItemId/%@", identifier];
	NSURLRequest *request = [NSURLRequest requestWithURL:[NSURL URLWithString:URLString]];
	[NSURLConnection sendAsynchronousRequest:request queue:[NSOperationQueue mainQueue] completionHandler:^(NSURLResponse *response, NSData *data, NSError *error) {
		if (error)
		{
			completionHandler ? completionHandler(nil, error) : nil;
			return;
		}
		
		id responseObject = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
		if (!responseObject || ![responseObject isKindOfClass:[NSArray class]])
		{
			NSError *parseError = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCannotParseResponse userInfo:nil];
			completionHandler ? completionHandler(nil, parseError) : nil;
			return;
		}
		
		NSMutableArray *segments = [NSMutableArray array];
		for (NSDictionary *highlight in responseObject)
		{
			// Note that the start date available from this JSON (streamStartDate) is not reliable and is retrieve using
			// another request
			NSDate *date = [NSDate dateWithTimeIntervalSince1970:[highlight[@"timestamp"] doubleValue]];
			NSDate *startDate = [NSDate dateWithTimeIntervalSince1970:[highlight[@"streamStartTime"] doubleValue]];
			CMTime time = CMTimeMake([date timeIntervalSinceDate:startDate], 1.);
			
			NSString *title = highlight[@"title"];
			UIImage *iconImage = nil;
			
			NSArray *titleComponents = [highlight[@"title"] componentsSeparatedByString:@"|"];
			if ([titleComponents count] > 1)
			{
				iconImage = [UIImage imageNamed:[titleComponents firstObject]];
				title = [titleComponents objectAtIndex:1];
			}
			
			Event *segment = [[Event alloc] initWithTime:time title:title identifier:highlight[@"id"] date:date];
			if (segment) {
				segment.iconImage = iconImage;
				[segments addObject:segment];
			}
		}
		
		completionHandler ? completionHandler([NSArray arrayWithArray:segments], nil) : nil;
	}];
}

@end
