/*
Copyright (c) 2007-2014, Stephane Sudre
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of the WhiteBox nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import <Foundation/Foundation.h>

#import "NDAlias+AliasFile.h"

#import "ICDirectoryServicesManager.h"

#include <SystemConfiguration/SystemConfiguration.h>

#include <unistd.h>
#include <pwd.h>

static void usage(const char * inProcessName)
{
    printf("usage: %s [-a][-u] <file or directory> alias\n",inProcessName);
	printf("       -a  --  Install an alias in all users home folder. alias will be read as a relative path.\n");
	printf("       -u  --  Install an alias in the current logged in user home folder. alias will be read as a relative path.n");
	
	exit(1);
}

int main (int argc, const char * argv[])
{
    NSAutoreleasePool * pool = [[NSAutoreleasePool alloc] init];
    BOOL tInstall4AllUsers=YES;
	BOOL tInstall4CurrentUser=YES;
	
    char ch;
	
	while ((ch = getopt(argc, (char ** const) argv, "au")) != -1)
	{
		switch (ch)
		{
			case 'a':
				
				tInstall4CurrentUser=NO;
				tInstall4AllUsers=YES;
				
				break;
			
			case 'u':
				
				tInstall4AllUsers=NO;
				tInstall4CurrentUser=YES;
				
				break;
				
			case '?':
			default:
				usage(argv[0]);
				break;
		}
	}
	
	
    argc-=optind;
    
    if (argc != 2)
    {
		usage(argv[0]);
		
		return -1;
    }
	else
	{
		char tResolvedPath[PATH_MAX];
		
		argv+=optind;
		
		if (realpath(argv[0],tResolvedPath)!=NULL)
		{
			NSString * tFile;
        
			tFile=[NSString stringWithUTF8String:tResolvedPath];
			
			if (tFile!=nil)
			{
				NSFileManager * tFileManager;
				NSString * tAliasFile;
				
				tFileManager=[NSFileManager defaultManager];
				
				tAliasFile=[NSString stringWithUTF8String:argv[1]];
				
				if (tAliasFile!=nil)
				{
					if (tInstall4CurrentUser==YES)
					{
						// We need to locate the current user home folder
						
						NSString * tUserName;
						uid_t tUID;
						gid_t tGID;
						
						tUserName=(NSString *)SCDynamicStoreCopyConsoleUser(NULL,&tUID,&tGID);
						
						if (tUserName!=nil && [tUserName isEqualToString:@"loginwindow"]==NO)
						{
							// Is it the console user?
							
							NSString * tHomeFolder;
							
							tHomeFolder=NSHomeDirectoryForUser(tUserName);
							
							if (tHomeFolder!=nil)
							{
								NSString * tAbsoluteAlias;
											
								tAbsoluteAlias=[tHomeFolder stringByAppendingPathComponent:tAliasFile];
								
								if ([tFileManager fileExistsAtPath:tAbsoluteAlias]==NO)
								{
									[[NDAlias aliasWithPath:tFile] writeToFile:tAbsoluteAlias];
									
									chown([tAbsoluteAlias fileSystemRepresentation],tUID,tGID);
								}
								else
								{
									(void)fprintf(stderr, "File \"%s\" already exists.\n",[tAbsoluteAlias fileSystemRepresentation]);
				
									exit(1);
								}
							}
							
							[tUserName release];
						}
						else
						{
							(void)fprintf(stderr, "No user is currently logged in\n");
						}
					}
					else if (tInstall4AllUsers==YES)
					{	
						NSArray * tAllUsersAccount;
						
						tAllUsersAccount=[[ICDirectoryServicesManager defaultManager] usersArray];
						
						if (tAllUsersAccount!=nil)
						{
							NSEnumerator * tEnumerator;
							
							tEnumerator=[tAllUsersAccount objectEnumerator];
							
							if (tEnumerator!=nil)
							{
								NSDictionary * tDictionary;
								BOOL tError=NO;
								
								while (tDictionary=[tEnumerator nextObject])
								{
									NSNumber * tUIDNumber;
									
									tUIDNumber=[tDictionary objectForKey:@"ID"];
									
									if (tUIDNumber!=nil)
									{
										int tUID;
										
										tUID=[tUIDNumber intValue];
										
										if (tUID>=500)
										{
											NSString * tUserName;
									
											tUserName=[tDictionary objectForKey:@"Name"];
											
											if (tUserName!=nil)
											{
												NSString * tHomeFolder;
									
												tHomeFolder=NSHomeDirectoryForUser(tUserName);
												
												if (tHomeFolder!=nil)
												{
													NSString * tAbsoluteAlias;
													
													tAbsoluteAlias=[tHomeFolder stringByAppendingPathComponent:tAliasFile];
													
													if ([tFileManager fileExistsAtPath:tAbsoluteAlias]==NO)
													{
														struct passwd * tPasswd;
														
														[[NDAlias aliasWithPath:tFile] writeToFile:tAbsoluteAlias];
														
														// Set correct owner and group
														
														tPasswd=getpwuid(tUID);
														
														if (tPasswd!=nil)
														{
															chown([tAbsoluteAlias fileSystemRepresentation],tUID,tPasswd->pw_gid);
														}
													}
													else
													{
														(void)fprintf(stderr, "file \"%s\" already exists.\n",[tAbsoluteAlias fileSystemRepresentation]);
														
														tError=YES;
													}
												}
											}
										}
									}
								}
								
								if (tError==YES)
								{
									exit(1);
								}
							}
						}
					}
					else
					{	
						if ([tFileManager fileExistsAtPath:tAliasFile]==NO)
						{
							[[NDAlias aliasWithPath:tFile] writeToFile:tAliasFile];
						}
						else
						{
							(void)fprintf(stderr, "File \"%s\" already exists.\n",argv[1]);
		
							exit(1);
						}
					}
				}
				else
				{
					(void)fprintf(stderr, "Memory must be really low...\n");
				}
			}
			else
			{
				(void)fprintf(stderr, "Memory must be really low...\n");
			}
		}
		else
		{
			switch(errno)
			{
				case ENOENT:
					// No such file or directory
					
					(void)fprintf(stderr,"\"%s\" was not found\n",argv[0]);
					break;
				
				default:
					// A COMPLETER
					break;
			}
			
			return -1;
		}
	}
    
    [pool release];
    
    return 0;
}
