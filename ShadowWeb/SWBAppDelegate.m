//
//  SWBAppDelegate.m
//  ShadowWeb
//
//  Created by clowwindy on 2/16/13.
//  Copyright (c) 2013 clowwindy. All rights reserved.
//
#import <Crashlytics/Crashlytics.h>

#import "GZIP.h"
#import "AppProxyCap.h"
#import "SWBAppDelegate.h"

#import "GCDWebServer.h"
#import "SWBViewController.h"
#import "ShadowsocksRunner.h"

#define kProxyModeKey @"proxy mode"

int polipo_main(int argc, char **argv);
void polipo_exit();

@implementation SWBAppDelegate {
    BOOL polipoRunning;
    BOOL polipoEnabled;
    NSURL *ssURL;
}

- (void)updateProxyMode {
    NSString *proxyMode = [[NSUserDefaults standardUserDefaults] objectForKey:kProxyModeKey];
    if (proxyMode == nil || [proxyMode isEqualToString:@"pac"]) {
        [AppProxyCap setPACURL:@"http://127.0.0.1:8090/proxy.pac"];
    } else if ([proxyMode isEqualToString:@"global"]) {
        [AppProxyCap setProxy:AppProxy_SOCKS Host:@"127.0.0.1" Port:9888];
    } else{
        [AppProxyCap setNoProxy];
    }
}

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    [self updateProxyMode];

//    [Crashlytics startWithAPIKey:@"fa65e4ab45ef1c9c69682529bee0751cd22d5d80"];

    [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler:^{

    }];
    polipoEnabled = YES;
    //新建一个队列
    dispatch_queue_t proxy = dispatch_queue_create("proxy", NULL);
    //将[self runProxy]放到队列中执行掉
    dispatch_async(proxy, ^{
        //这个方法是一个死循环，不会退出。
        //估计这里会去调local.m的函数，实现流量代理了
        [self runProxy];
    });

//    [self proxyHttpStart];
//    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(updatePolipo) userInfo:nil repeats:YES];
    
    //在iOS上搭一个轻量级的服务器 see https://github.com/swisspol/GCDWebServer
    NSData *pacData = [[NSData dataWithContentsOfURL:[[NSBundle mainBundle] URLForResource:@"proxy" withExtension:@"pac.gz"]] gunzippedData];
    GCDWebServer *webServer = [[GCDWebServer alloc] init];
    
    //⚠️Even though most clients will process the script regardless of the MIME type returned in the HTTP reply, for the sake of completeness and to maximize compatibility, the HTTP server should be configured to declare the MIME type of this file to be either application/x-ns-proxy-autoconfig or application/x-javascript-config.
    //这里请求pac文件返回固定的文件内容即可
    //这个pac文件规定了代理的服务器
    [webServer addHandlerForMethod:@"GET" path:@"/proxy.pac" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
        GCDWebServerDataResponse *res = [GCDWebServerDataResponse responseWithData:pacData contentType:@"application/x-ns-proxy-autoconfig"];
        return res;

         }
    ];

    [webServer addHandlerForMethod:@"GET" path:@"/apn" requestClass:[GCDWebServerRequest class] processBlock:^GCDWebServerResponse *(GCDWebServerRequest *request) {
            NSString *apnID = request.query[@"id"];
            NSData *mobileconfig = [NSData dataWithContentsOfURL:[[NSBundle mainBundle] URLForResource:apnID withExtension:@"mobileconfig"]];
            return [GCDWebServerDataResponse responseWithData:mobileconfig contentType:@"application/x-apple-aspen-config"];
         }
    ];


    [webServer startWithPort:8090 bonjourName:@"webserver"];
//    dispatch_queue_t web = dispatch_queue_create("web", NULL);
//    dispatch_async(web, ^{
//        @try {
//            dispatch_async(dispatch_get_main_queue(), ^{
//            });
//        } @catch (NSException *e) {
//            NSLog(@"webserver quit with error: %@", e);
//        }
//    });

    self.networkActivityIndicatorManager = [[SWBNetworkActivityIndicatorManager alloc] init];


    self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
    self.viewController = [[SWBViewController alloc] init];
    self.window.rootViewController = self.viewController;
    [self.window makeKeyAndVisible];
        
    return YES;
}


- (BOOL)application:(UIApplication *)application handleOpenURL:(NSURL *)url {
    return [self application:application openURL:url sourceApplication:nil annotation:nil];
}

- (BOOL)application:(UIApplication *)application openURL:(NSURL *)url sourceApplication:(NSString *)sourceApplication annotation:(id)annotation {
    ssURL = url;
    UIAlertView *alertView = [[UIAlertView alloc] initWithTitle:_L(Use this server?) message:[url absoluteString] delegate:self cancelButtonTitle:_L(Cancel) otherButtonTitles:_L(OK), nil];
    [alertView show];
    return YES;
}

- (void)alertView:(UIAlertView *)alertView didDismissWithButtonIndex:(NSInteger)buttonIndex {
    if (buttonIndex == 1) {
        [ShadowsocksRunner openSSURL:ssURL];
    } else {
        // Do nothing
    }
}


- (void)applicationWillResignActive:(UIApplication *)application {
    // Sent when the application is about to move from active to inactive state. This can occur for certain types of temporary interruptions (such as an incoming phone call or SMS message) or when the user quits the application and it begins the transition to the background state.
    // Use this method to pause ongoing tasks, disable timers, and throttle down OpenGL ES frame rates. Games should use this method to pause the game.
}

- (void)applicationDidEnterBackground:(UIApplication *)application {
    // Use this method to release shared resources, save user data, invalidate timers, and store enough application state information to restore your application to its current state in case it is terminated later. 
    // If your application supports background execution, this method is called instead of applicationWillTerminate: when the user quits.
    [((SWBViewController *) self.window.rootViewController) saveData];
}

- (void)applicationWillEnterForeground:(UIApplication *)application {
    // Called as part of the transition from the background to the inactive state; here you can undo many of the changes made on entering the background.
}

- (void)applicationDidBecomeActive:(UIApplication *)application {
    // Restart any tasks that were paused (or not yet started) while the application was inactive. If the application was previously in the background, optionally refresh the user interface.
}

- (void)applicationWillTerminate:(UIApplication *)application {
    // Called when the application is about to terminate. Save data if appropriate. See also applicationDidEnterBackground:.
    [((SWBViewController *) self.window.rootViewController) saveData];
}

#pragma mark - Run proxy

- (void)runProxy {
    //去配置ip 端口等信息，配置到了local.m里
    [ShadowsocksRunner reloadConfig];
    for (; ;) {
        if ([ShadowsocksRunner runProxy]) {
            sleep(1);
        } else {
            sleep(2);
        }
    }
}

#pragma mark polipo

-(void) updatePolipo {
    if (!polipoRunning) {
        [self proxyHttpStart];
    }
}

- (void) proxyHttpStart
{
    if (polipoRunning) {
        NSLog(@"already running");
        return;
    }
    polipoRunning = YES;
    if (polipoEnabled) {
        [NSThread detachNewThreadSelector:@selector(proxyHttpRun) toTarget:self withObject:nil];
    } else{
        [NSThread detachNewThreadSelector:@selector(proxyHttpRunDisabled) toTarget:self withObject:nil];
    }
}

- (void) proxyHttpStop
{
    if (!polipoRunning) {
        NSLog(@"not running");
        return;
    }
    polipo_exit();
}

- (void) proxyHttpRunDisabled {
 @autoreleasepool {
         polipoRunning = YES;
        NSLog(@"http proxy start");
        NSString *configuration = [[NSBundle mainBundle] pathForResource:@"polipo_disable" ofType:@"config"];
        char *args[5] = {
            "test",
            "-c",
            (char*)[configuration UTF8String],
            "proxyAddress=127.0.0.1",
            (char*)[[NSString stringWithFormat:@"proxyPort=%d", 8081] UTF8String],
        };
        polipo_main(5, args);
        NSLog(@"http proxy stop");
        polipoRunning = NO;
    }}

- (void) proxyHttpRun
{
    @autoreleasepool {
        polipoRunning = YES;
        NSLog(@"http proxy start");
        NSString *configuration = [[NSBundle mainBundle] pathForResource:@"polipo" ofType:@"config"];
        char *args[5] = {
            "test",
            "-c",
            (char*)[configuration UTF8String],
            "proxyAddress=0.0.0.0",
            (char*)[[NSString stringWithFormat:@"proxyPort=%d", 8081] UTF8String],
        };
        polipo_main(5, args);
        NSLog(@"http proxy stop");
        polipoRunning = NO;
    }
}

- (void)setPolipo:(BOOL)enabled {
    polipoEnabled = enabled;

    [self proxyHttpStop];
}

@end
