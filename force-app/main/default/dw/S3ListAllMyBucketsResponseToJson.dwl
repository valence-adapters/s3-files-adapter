%dw 2.5
import * from dw::util::Values
input payload application/xml
output application/json
---
// simplfy buckets data structure to easily deserialize
// replace entire "Buckets" node with an array of bucket objects
payload.ListAllMyBucketsResult update
    "Buckets" with payload.ListAllMyBucketsResult.Buckets.*Bucket

/* INPUT:
<ListAllMyBucketsResult>
   <Buckets>
      <Bucket>
         <CreationDate>2019-12-11T23:32:47+00:00</CreationDate>
         <Name>DOC-EXAMPLE-BUCKET</Name>
      </Bucket>
      <Bucket>
         <CreationDate>2019-11-10T23:32:13+00:00</CreationDate>
         <Name>DOC-EXAMPLE-BUCKET2</Name>
      </Bucket>
   </Buckets>
   <Owner>
      <DisplayName>Account+Name</DisplayName>
      <ID>AIDACKCEVSQ6C2EXAMPLE</ID>
   </Owner>
</ListAllMyBucketsResult>
*/

/* OUTPUT:
{
  "Buckets": [
    {
      "CreationDate": "2019-12-11T23:32:47+00:00",
      "Name": "DOC-EXAMPLE-BUCKET"
    },
    {
      "CreationDate": "2019-11-10T23:32:13+00:00",
      "Name": "DOC-EXAMPLE-BUCKET2"
    }
  ],
  "Owner": {
    "DisplayName": "Account+Name",
    "ID": "AIDACKCEVSQ6C2EXAMPLE"
  }
}
*/