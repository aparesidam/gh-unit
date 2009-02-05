//
//  GHTestUtils.m
//  GHUnit
//
//  Created by Gabriel Handford on 1/30/09.
//  Copyright 2008 Gabriel Handford
//
//  Permission is hereby granted, free of charge, to any person
//  obtaining a copy of this software and associated documentation
//  files (the "Software"), to deal in the Software without
//  restriction, including without limitation the rights to use,
//  copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the
//  Software is furnished to do so, subject to the following
//  conditions:
//
//  The above copyright notice and this permission notice shall be
//  included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
//  EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
//  OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
//  NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
//  HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
//  WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
//  FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
//  OTHER DEALINGS IN THE SOFTWARE.
//

//
// Portions of this file fall under the following license, marked with:
// GTM_BEGIN : GTM_END
//
//  Copyright 2008 Google Inc.
//
//  Licensed under the Apache License, Version 2.0 (the "License"); you may not
//  use this file except in compliance with the License.  You may obtain a copy
//  of the License at
// 
//  http://www.apache.org/licenses/LICENSE-2.0
// 
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS, WITHOUT
//  WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.  See the
//  License for the specific language governing permissions and limitations under
//  the License.
//

#import "GHTestUtils.h"

#import <objc/runtime.h>

// GTM_BEGIN

// Used for sorting methods below
static int MethodSort(const void *a, const void *b) {
  const char *nameA = sel_getName(method_getName(*(Method*)a));
  const char *nameB = sel_getName(method_getName(*(Method*)b));
  return strcmp(nameA, nameB);
}

// GTM_END

BOOL isSenTestCaseClass(Class aClass) {
	return isTestFixtureOfClass(aClass, NSClassFromString(@"SenTestCase"));
}

BOOL isGTMTestCaseClass(Class aClass) {
	return isTestFixtureOfClass(aClass, NSClassFromString(@"GTMTestCase"));
}

// GTM_BEGIN

// Return YES if class is subclass (1 or more generations) of GHTestCase
BOOL isTestFixture(Class aClass) {
	return isTestFixtureOfClass(aClass, NSClassFromString(@"GHTestCase"));
}

BOOL isTestFixtureOfClass(Class aClass, Class testCaseClass) {
	if (testCaseClass == NULL) return NO;
  BOOL iscase = NO;
  Class superclass;
  for (superclass = aClass; 
       !iscase && superclass; 
       superclass = class_getSuperclass(superclass)) {
    iscase = superclass == testCaseClass ? YES : NO;
  }
  return iscase;
}

// GTM_END

@implementation GHTestUtils

+ (NSArray *)loadTestCases {
	NSMutableArray *testCases = [NSMutableArray array];

	// GTM_BEGIN
	int count = objc_getClassList(NULL, 0);
  NSMutableData *classData = [NSMutableData dataWithLength:sizeof(Class) * count];
  Class *classes = (Class*)[classData mutableBytes];
  //_GTMDevAssert(classes, @"Couldn't allocate class list");
  objc_getClassList(classes, count);
	
  for (int i = 0; i < count; ++i) {
    Class currClass = classes[i];
		id testcase = nil;
		
    if (isTestFixture(currClass) || isSenTestCaseClass(currClass) || isGTMTestCaseClass(currClass)) {			
			testcase = [[currClass alloc] init];
		} else {
			continue;
		}
		
		[testCases addObject:testcase];
		[testcase release];
  }
	return testCases;
	// GTM_END
}

// GTM_BEGIN

+ (NSArray *)loadTestsFromTarget:(id)target {
	NSMutableArray *tests = [NSMutableArray array];
	
	unsigned int methodCount;
	Method *methods = class_copyMethodList([target class], &methodCount);
	if (!methods) {
		return nil;
	}
	// This handles disposing of methods for us even if an
	// exception should fly. 
	[NSData dataWithBytesNoCopy:methods
											 length:sizeof(Method) * methodCount];
	// Sort our methods so they are called in Alphabetical order just
	// because we can.
	qsort(methods, methodCount, sizeof(Method), MethodSort);
	for (size_t j = 0; j < methodCount; ++j) {
		Method currMethod = methods[j];
		SEL sel = method_getName(currMethod);
		char *returnType = NULL;
		const char *name = sel_getName(sel);
		// If it starts with test, takes 2 args (target and sel) and returns
		// void run it.
		if (strstr(name, "test") == name) {
			returnType = method_copyReturnType(currMethod);
			if (returnType) {
				// This handles disposing of returnType for us even if an
				// exception should fly. Length +1 for the terminator, not that
				// the length really matters here, as we never reference inside
				// the data block.
				[NSData dataWithBytesNoCopy:returnType
														 length:strlen(returnType) + 1];
			}
		}
		if (returnType  // True if name starts with "test"
				&& strcmp(returnType, @encode(void)) == 0
				&& method_getNumberOfArguments(currMethod) == 2) {
			
			GHTest *test = [GHTest testWithTarget:target selector:sel];
			[tests addObject:test];
		}
	}
	
	return tests;
}

+ (BOOL)runTest:(id)target selector:(SEL)selector exception:(NSException **)exception interval:(NSTimeInterval *)interval {
	NSDate *startDate = [NSDate date];	
	NSException *testException = nil;
	// GTM_BEGIN
  @try {
    // Wrap things in autorelease pools because they may
    // have an STMacro in their dealloc which may get called
    // when the pool is cleaned up
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    // We don't log exceptions here, instead we let the person that called
    // this log the exception.  This ensures they are only logged once but the
    // outer layers get the exceptions to report counts, etc.
    @try {
			if ([target respondsToSelector:@selector(setUp)])
				[target performSelector:@selector(setUp)];
      @try {	
        [target performSelector:selector];
      } @catch (NSException *exception) {
        testException = [exception retain];
      }
			if ([target respondsToSelector:@selector(tearDown)])
				[target performSelector:@selector(tearDown)];
    } @catch (NSException *exception) {
      testException = [exception retain];
    }
    [pool release];
  } @catch (NSException *exception) {
    testException = [exception retain];
  }
	// GTM_END	
	if (interval) *interval = [[NSDate date] timeIntervalSinceDate:startDate];
	
	if (exception) *exception = testException;
	BOOL passed = (!testException);
	return passed;
}

// GTM_END

@end
