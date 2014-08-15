/*
Copyright (c) 2004-2014, Stephane Sudre
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

- Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
- Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
- Neither the name of the WhiteBox nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/

#import "ICDirectoryServicesManager.h"

const long PBDS_BUFFER_SIZE = 8192;

@implementation NSDictionary(ICDirectoryServicesManager) 

- (NSComparisonResult) compareUserGroupName:(NSDictionary *) other
{
    return [((NSString *)[self objectForKey:@"Name"]) compare:[other objectForKey:@"Name"]];
}

@end

@implementation ICDirectoryServicesManager

+ (ICDirectoryServicesManager *) defaultManager
{
    static ICDirectoryServicesManager * sDSManager=nil;
    
    if (sDSManager==nil)
    {
        sDSManager=[ICDirectoryServicesManager new];
        
        [sDSManager _buildCaches];
    }
    
    return sDSManager;
}

- (id) init
{
    self=[super init];
    
    if (self!=nil)
    {
        tDirStatus tStatus;
        
        usersCache_=[[NSMutableDictionary alloc] initWithCapacity:50];
		
		groupsCache_=[[NSMutableDictionary alloc] initWithCapacity:50];
		
		tStatus = dsOpenDirService(&directoryServicesReference_);
    
        if (tStatus == eDSNoErr && usersCache_!=nil && groupsCache_!=nil)
        {
            dataBuffer_ = dsDataBufferAllocate(directoryServicesReference_, PBDS_BUFFER_SIZE );
        
            if (dataBuffer_!=NULL)
            {
                UInt32 tDirectoryNodeCount;
                UInt32 tDirectoryNodeIndex;
                long error;
                char * tDirectoryNodePath;
                
                tDirectoryNodeCount=0;
                
                tDirectoryNodePath=NULL;
                
                do
                {
                    error = dsFindDirNodes(directoryServicesReference_,dataBuffer_,NULL,eDSLocalNodeNames,&tDirectoryNodeCount,NULL);
                    
                    if (error == eDSBufferTooSmall)
                    {
                        [self increaseDataBuffer];
                    }
                }
                while (error == eDSBufferTooSmall);
                
                if ( error == eDSNoErr )
                {
                    if (tDirectoryNodeCount!= 0)
                    {
                        tDataList * tDirectoryName;
                        
                        tDirectoryName = dsDataListAllocate(directoryServicesReference_);
                        
                        if (tDirectoryName!=NULL)
                        {
                            for (tDirectoryNodeIndex = 1;(tDirectoryNodeIndex <= tDirectoryNodeCount) && (error == eDSNoErr); tDirectoryNodeIndex++ )
                            {
                                error = dsGetDirNodeName(directoryServicesReference_,dataBuffer_,tDirectoryNodeIndex, &tDirectoryName );
                                
                                if ( error == eDSNoErr )
                                {
                                    tDirectoryNodePath = dsGetPathFromList(directoryServicesReference_,tDirectoryName, "/" );
                                    
                                    if (tDirectoryNodePath!= NULL)
                                    {
                                        dsDataListDeallocate(directoryServicesReference_, tDirectoryName );
                                        
                                        break;
                                    }
                                    else
                                    {
                                       NSLog(@"[ICDirectoryServicesUtilities.m:70 dsGetPathFromList failed");
                                    }
                                }
                            }
                        }
                        else
                        {
                            NSLog(@"[ICDirectoryServicesUtilities.m:77 dsDataListAllocate failed");
                            
                            error = 1;
                        }
                    }
                }
                
                if (tDirectoryNodePath!=NULL)
                {
                    long error = eDSNoErr;
                    tDataList * tNodeList;
    
                    tNodeList = dsBuildFromPath(directoryServicesReference_,tDirectoryNodePath, "/" );
                    
                    if ( tNodeList != NULL )
                    {
                        error = dsOpenDirNode( directoryServicesReference_, tNodeList, &localNodeReference_);
                        
                        dsDataListDeallocate(directoryServicesReference_,tNodeList);
                        
                        if (error==eDSNoErr)
                        {
                            return self;
                        }
                    }
                }
            }
            
            dsCloseDirService(directoryServicesReference_);
        }
        
        return nil;
    }
    
    return self;
}

- (void) dealloc
{
    [usersCache_ release];
	
	[groupsCache_ release];
	
	if (localNodeReference_!=0)
    {
        dsCloseDirNode(localNodeReference_);
    }
    
    if (dataBuffer_!=NULL)
    {
        dsDataBufferDeAllocate(directoryServicesReference_,dataBuffer_);
    }
    
    if (directoryServicesReference_!=0)
    {
        dsCloseDirService(directoryServicesReference_);
    }
	
	[super dealloc];
}

#pragma mark -

- (void) increaseDataBuffer
{
    UInt32 tBufferSize = dataBuffer_->fBufferSize;
                        
    dsDataBufferDeAllocate(directoryServicesReference_, dataBuffer_);
    
    dataBuffer_=dsDataBufferAllocate( directoryServicesReference_, tBufferSize*2 );
}

#pragma mark -

- (void) _buildCaches
{
    tDirStatus error = eDSNoErr;
    UInt32 tRecordCount;
    tContextData context = 0;
    tDataList * tRecordName;
    
    // Users
    
    tRecordCount=0;
    
    tRecordName = dsBuildListFromStrings(directoryServicesReference_,kDSRecordsAll,NULL);
    
    if (tRecordName != NULL)
    {
        tDataList * tRecordType;
        
        tRecordType = dsBuildListFromStrings(directoryServicesReference_,kDSStdRecordTypeUsers,NULL);
        
        if (tRecordType!=NULL)
        {
            tDataList * tAttributesType;
            
            // We're interesting by the uid and account name
            
            tAttributesType = dsBuildListFromStrings(directoryServicesReference_, kDS1AttrUniqueID, NULL);
            
            if (tAttributesType!=NULL)
            {
                do
                {
                    error = dsGetRecordList(localNodeReference_,dataBuffer_,tRecordName,eDSExact,tRecordType,tAttributesType,0,&tRecordCount,&context);
                    
                    if ( error == eDSNoErr )
                    {
                        NSMutableDictionary * tUsersDictionary;
						
						tUsersDictionary=[self _dictionaryWithLocalRef:localNodeReference_ data:dataBuffer_ count:tRecordCount];
						
						if (tUsersDictionary!=nil)
						{
							[usersCache_ addEntriesFromDictionary:tUsersDictionary];
						}
						else
						{
                            error=eUndefinedError;
                        }
                    } 
                    else if ( error == eDSBufferTooSmall )
                    {
                        [self increaseDataBuffer];
                    }
                }
                while (((error == eDSNoErr) && (context != 0)) || (error == eDSBufferTooSmall) );

                dsDataListDeallocate(directoryServicesReference_,tAttributesType);
            }

            dsDataListDeallocate(directoryServicesReference_,tRecordType);
        }

        dsDataListDeallocate(directoryServicesReference_, tRecordName );
    }
    
    // Groups
    
    error = eDSNoErr;
    
    context = 0;
    
    tRecordCount=0;
    
    tRecordName = dsBuildListFromStrings(directoryServicesReference_,kDSRecordsAll,NULL);
    
    if (tRecordName != NULL)
    {
        tDataList * tRecordType;
        
        tRecordType = dsBuildListFromStrings(directoryServicesReference_,kDSStdRecordTypeGroups,NULL);
        
        if (tRecordType!=NULL)
        {
            tDataList * tAttributesType;
            
            // We're interested by the uid and account name
            
            tAttributesType = dsBuildListFromStrings(directoryServicesReference_, kDS1AttrPrimaryGroupID, NULL);
            
            if (tAttributesType!=NULL)
            {
                do
                {
                    error = dsGetRecordList(localNodeReference_,dataBuffer_,tRecordName,eDSExact,tRecordType,tAttributesType,0,&tRecordCount,&context);
                    
                    if ( error == eDSNoErr )
                    {
                        NSMutableDictionary * tGroupsDictionary;
						
						tGroupsDictionary=[self _dictionaryWithLocalRef:localNodeReference_ data:dataBuffer_ count:tRecordCount];
						
						if (tGroupsDictionary!=nil)
						{
							[groupsCache_ addEntriesFromDictionary:tGroupsDictionary];
						}
						else
						{
                            error=eUndefinedError;
                        }
                    } 
                    else if ( error == eDSBufferTooSmall )
                    {
                        [self increaseDataBuffer];
                    }
                }
                while (((error == eDSNoErr) && (context != 0)) || (error == eDSBufferTooSmall) );

                dsDataListDeallocate(directoryServicesReference_,tAttributesType);
            }

            dsDataListDeallocate(directoryServicesReference_,tRecordType);
        }

        dsDataListDeallocate(directoryServicesReference_, tRecordName );
    }
}

- (NSMutableDictionary *) _dictionaryWithLocalRef:(tDirNodeReference) inReference data:(tDataBufferPtr) inData count:(UInt32) inCount
{
    NSMutableDictionary * nMutableDictionary=nil;
    UInt32 i;
    tDirStatus error;
    tAttributeEntry * attributeEntryPtr	= NULL;
    tAttributeValueEntry * valueEntryPtr = NULL;
    
    error = eDSNoErr;
    
    nMutableDictionary=[NSMutableDictionary dictionaryWithCapacity:inCount];
    
    for (i = 1; (i <= inCount) && (error == eDSNoErr);i++)
    {
        tAttributeListRef attributeListRef = 0;
        tRecordEntry * recordEntryPtr = NULL;
        
        error = dsGetRecordEntry(inReference, inData, i, &attributeListRef, &recordEntryPtr);
        
        if ( error == eDSNoErr && recordEntryPtr!=NULL)
        {
            char * tRecordName=NULL;
            UInt32 j;
            
            error = dsGetRecordNameFromEntry( recordEntryPtr, &tRecordName );
            
            if (error==eDSNoErr && tRecordName!=NULL)
            {
                for (j = 1; (j <= recordEntryPtr->fRecordAttributeCount) && (error == eDSNoErr);j++)
                {
                    tAttributeValueListRef valueRef = 0;
                    
                    error = dsGetAttributeEntry(inReference,inData, attributeListRef, j, &valueRef, &attributeEntryPtr);
                    
                    if (error == eDSNoErr && attributeEntryPtr)
                    {
                        UInt32 k;
                        
                        for (k = 1; (k <= attributeEntryPtr->fAttributeValueCount) && (error == eDSNoErr);k++)
                        {
                            error = dsGetAttributeValue(inReference,inData,k,valueRef,&valueEntryPtr);
                            
                            if ( error == eDSNoErr && valueEntryPtr!=NULL)
                            {
                                [nMutableDictionary setObject:[NSString stringWithUTF8String:tRecordName] forKey:[NSNumber numberWithInt:atoi(valueEntryPtr->fAttributeValueData.fBufferData)]];
                                
                                dsDeallocAttributeValueEntry(directoryServicesReference_,valueEntryPtr );
                                
                                valueEntryPtr = NULL;
                                
                                break;
                            }
                            else
                            {
                                // A COMPLETER
                            }
                        }
                        
                        dsDeallocAttributeEntry(directoryServicesReference_,attributeEntryPtr);
                        
                        attributeEntryPtr = NULL;
                        
                        dsCloseAttributeValueList(valueRef);
                        
                        valueRef = 0;
                    }
                    else
                    {
                        // A COMPLETER
                    }
                }
                
                free(tRecordName);
            }
            
            dsDeallocRecordEntry(directoryServicesReference_,recordEntryPtr);
            
            recordEntryPtr = NULL;
            
            dsCloseAttributeList(attributeListRef);
        }
        else
        {
            // A COMPLETER
        }
    }

    return nMutableDictionary;
}

- (NSMutableArray *) usersArray
{
    NSMutableArray * tMutableArray=nil;
    NSUInteger tCount;
    
    tCount=[usersCache_ count];
    
    tMutableArray=[NSMutableArray arrayWithCapacity:tCount];
    
    if (tMutableArray!=nil && tCount>0)
    {
        NSEnumerator * tKeyEnumerator;
        NSNumber * tKey;
        
        tKeyEnumerator=[usersCache_ keyEnumerator];
        
        while (tKey=[tKeyEnumerator nextObject])
        {
            NSDictionary * tDictionary;
            
            tDictionary=[NSDictionary dictionaryWithObjectsAndKeys:[usersCache_ objectForKey:tKey],@"Name",
                                                                   tKey,@"ID",
                                                                   nil];
                                                                   
            [tMutableArray addObject:tDictionary];
        
        }
    }
    
    return tMutableArray;
}

- (NSMutableArray *) groupsArray
{
    NSMutableArray * tMutableArray=nil;
    NSUInteger tCount;
    
    tCount=[groupsCache_ count];
    
    tMutableArray=[NSMutableArray arrayWithCapacity:tCount];
    
    if (tMutableArray!=nil && tCount>0)
    {
        NSEnumerator * tKeyEnumerator;
        NSNumber * tKey;
        
        tKeyEnumerator=[groupsCache_ keyEnumerator];
        
        while (tKey=[tKeyEnumerator nextObject])
        {
            NSDictionary * tDictionary;
            
            tDictionary=[NSDictionary dictionaryWithObjectsAndKeys:[groupsCache_ objectForKey:tKey],@"Name",
                                                                   tKey,@"ID",
                                                                   nil];
                                                                   
            [tMutableArray addObject:tDictionary];
        
        }
    }
    
    return tMutableArray;
}

- (NSString *) userAccountForUID:(int) inUID
{
    return [usersCache_ objectForKey:[NSNumber numberWithInt:inUID]];
}

- (NSString *) groupForGID:(int) inGID
{
    return [groupsCache_ objectForKey:[NSNumber numberWithInt:inGID]];
}

@end
