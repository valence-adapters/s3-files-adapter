# S3 File Adapter

This is a custom extension for [Valence](https://valence.app), a [managed package on the Salesforce AppExchange](https://appexchange.salesforce.com/appxListingDetail?listingId=a0N3A00000EORP4UAP) that provides integration middleware natively in a Salesforce org.

To learn more about developing extensions for the Valence platform, have a look at [the Valence documentation](https://docs.valence.app).

## Installing

Click this button to install the AWS S3 Adapter into your org.

<a href="https://githubsfdeploy.herokuapp.com?owner=valence-adapters&repo=s3-files-adapter&ref=main">
  <img alt="Deploy to Salesforce"
       src="https://raw.githubusercontent.com/afawcett/githubsfdeploy/master/deploy.png">
</a>

## What Does This Adapter Do?

Connects Valence and and S3 bucket. Read flat files like comma-separated, tab-separated, and pipe-delimited files.

Selecting an S3 bucket and configuring a directory path, this adapter will process all files in that directory, respecting modified dates and only processing files newer than the last successful sync.

### Setting Up Authentication

Salesforce provides support for AWS API protocols with External and Named credentials. Following [the instructions](https://help.salesforce.com/s/articleView?id=sf.nc_create_edit_awssig4_ext_cred.htm&type=5) to setup the External Credential, make sure to configure the "service" as "s3" and select the correct region that your bucket lives in.

Once you have correctly setup the Named Credential you'll need to create a Permission Set and assign the `External Credential Principal Access` that you created as part of the External Credential.

Once you have the Permission Set setup you'll need to provide access to the user that runs the Valence Link as well as the `Automated Process` user that Salesforce uses to run background jobs.
