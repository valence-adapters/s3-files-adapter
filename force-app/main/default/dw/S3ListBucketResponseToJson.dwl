%dw 2.5
import * from dw::util::Values
input payload application/xml
output application/json
---
// unpack ListBucketResult top-level object
// remove individual "Contents" and "CommonPrefixes" nodes and add back as a arrays
(payload.ListBucketResult - "Contents" - "CommonPrefixes") ++
    { "Contents": payload.ListBucketResult.*Contents, "CommonPrefixes": payload.ListBucketResult.*CommonPrefixes.Prefix }

/* INPUT:
<?xml version="1.0" encoding="UTF-8"?>
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">
    <Name>bucket-123</Name>
    <Prefix>folder1/folder2/</Prefix>
    <KeyCount>1</KeyCount>
    <MaxKeys>1000</MaxKeys>
    <IsTruncated>false</IsTruncated>
    <Contents>
        <Key>folder1/folder2/File1.csv</Key>
        <LastModified>2024-10-29T20:31:45.000Z</LastModified>
        <ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>
        <Size>1719949</Size>
        <StorageClass>STANDARD</StorageClass>
    </Contents>
    <CommonPrefixes>
        <Prefix>folder1/folder2/lots-of-files/</Prefix>
    </CommonPrefixes>
</ListBucketResult>
*/

/* OUTPUT:
{
  "Name": "bucket-123",
  "Prefix": "folder1/folder2/",
  "KeyCount": "3",
  "MaxKeys": "1000",
  "IsTruncated": "false",
  "Contents": [
    {
      "Key": "folder1/folder2/File1.csv",
      "LastModified": "2023-12-15T16:59:31.000Z",
      "ETag": "\"d41d8cd98f00b204e9800998ecf8427e\"",
      "Size": "0",
      "StorageClass": "STANDARD"
    }
  ],
  "CommonPrefixes": [
    "folder1/folder2/lots-of-files/"
  ]
}
*/