@IsTest
public class ValenceS3AdapterTests {
	////////////
	// Config //
	////////////

	@IsTest
	static void testSourceConfig() {
		ValenceS3Adapter adapter = new ValenceS3Adapter();

		Assert.areEqual('c:s3AdapterConfigurator', adapter.getSourceConfigurationLightningComponent(null));
		Assert.areEqual(null, adapter.getSourceConfigurationStructure(null));

		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		adapter.setSourceConfiguration(null, JSON.serialize(cfg));

		String expectedConfig = '<dl class="slds-dl_horizontal slds-m-top_x-small" style="--lwc-fontWeightBold: 400;">';
		expectedConfig += '<dt class="slds-dl_horizontal__label tweaked-text-title_caps slds-m-top_x-small slds-size_5-of-12">Source File(s):</dt>';
		expectedConfig += '<dd class="slds-dl_horizontal__detail slds-m-left_none slds-m-top_x-small slds-size_7-of-12">All files in the root of the bucket</dd>';
		expectedConfig += '</dl>';
		String configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.areEqual(expectedConfig, configOutput);

		// path
		cfg.path = 'folder1/folder2/';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(
			configOutput.contains('All files in "folder1/folder2/"'),
			'Expected config to contain `All files in "folder1/folder2/"`, was ' + configOutput
		);
		cfg.path = null;

		// mbsPerBatch
		cfg.mbsPerBatch = '1.5';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(configOutput.contains('Chunk Size'), 'Expected config to contain `Chunk Size`, was ' + configOutput);
		Assert.isTrue(configOutput.contains('1.5'), 'Expected config to contain `1.5`, was ' + configOutput);
		cfg.mbsPerBatch = null;

		// fieldSeparator
		cfg.fieldSeparator = '|';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(
			configOutput.contains('Break Fields On'),
			'Expected config to contain `Break Fields On`, was ' + configOutput
		);
		Assert.isTrue(configOutput.contains('|'), 'Expected config to contain `|`, was ' + configOutput);
		cfg.fieldSeparator = null;

		// maxObjectsPerPlan
		cfg.maxObjectsPerPlan = '25';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(
			configOutput.contains('Scope Plan Count'),
			'Expected config to contain `Scope Plan Count`, was ' + configOutput
		);
		Assert.isTrue(configOutput.contains('25'), 'Expected config to contain `25`, was ' + configOutput);
		cfg.maxObjectsPerPlan = null;

		// bytesForFetchPrefix
		cfg.bytesForFetchPrefix = '25';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(
			configOutput.contains('Prefetched Bytes'),
			'Expected config to contain `Scope Plan Count`, was ' + configOutput
		);
		Assert.isTrue(configOutput.contains('25'), 'Expected config to contain `25`, was ' + configOutput);
		cfg.bytesForFetchPrefix = null;

		// bytesForHeaderFetch
		cfg.bytesForHeaderFetch = '25';
		configOutput = adapter.explainSourceConfiguration(null, JSON.serialize(cfg));
		Assert.isTrue(
			configOutput.contains('Max Header Bytes'),
			'Expected config to contain `Scope Plan Count`, was ' + configOutput
		);
		Assert.isTrue(configOutput.contains('25'), 'Expected config to contain `25`, was ' + configOutput);
		cfg.bytesForHeaderFetch = null;
	}

	///////////
	// Scope //
	///////////

	@IsTest
	static void testScopes() {
		ValenceS3Adapter adapter = new ValenceS3Adapter();
		// test Scope and PlanScope in and out

		ValenceS3Adapter.Scope bScope = new ValenceS3Adapter.Scope();
		bScope.key = 'key123';
		ValenceS3Adapter.Scope pScope = new ValenceS3Adapter.Scope();
		pScope.nextContinuationToken = 'token123';

		String bScopeString = adapter.serializeScope(bScope);
		Assert.areEqual(JSON.serialize(bScope), bScopeString);

		String pScopeString = adapter.serializeScope(pScope);
		Assert.areEqual(JSON.serialize(pScope), pScopeString);

		bScope = (ValenceS3Adapter.Scope) adapter.deserializeScope(bScopeString);
		Assert.areEqual('key123', bScope.key);

		pScope = (ValenceS3Adapter.Scope) adapter.deserializeScope(pScopeString);
		Assert.areEqual('token123', pScope.nextContinuationToken);
	}

	////////////
	// Schema //
	////////////

	@IsTest
	static void testGetTables() {
		String namedCredential = 'TEST_CRED';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListAllMyBucketsResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'    <Owner>' +
				'        <ID>8accf84985cf9d7d0650e822988a02e2bde5564f12c170124bc96f63d5f01988</ID>' +
				'    </Owner>' +
				'    <Buckets>' +
				'        <Bucket>' +
				'            <Name>test-bucket-1</Name>' +
				'            <CreationDate>2023-11-01T21:25:00.000Z</CreationDate>' +
				'        </Bucket>' +
				'        <Bucket>' +
				'            <Name>test-bucket-2</Name>' +
				'            <CreationDate>2023-11-01T21:26:00.000Z</CreationDate>' +
				'        </Bucket>' +
				'    </Buckets>' +
				'</ListAllMyBucketsResult>'
		);
		mock.responseMap.put('callout:' + namedCredential, resp);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		List<valence.Table> tables = adapter.getTables();
		Assert.areEqual(2, tables.size());
		Assert.areEqual('test-bucket-1', tables[0].name);
		Assert.areEqual('test-bucket-2', tables[1].name);
	}

	@IsTest
	static void testGetFields() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1719949</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);
		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=100&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8'),
			resp
		);

		// mock get byte range of file
		resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody('1,2,3,4,5,6\nA1,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6\n');
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File1.csv', resp);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		adapter.setSourceConfiguration(ctx, JSON.serialize(cfg));
		List<valence.Field> fields = adapter.getFields(ctx.linkSourceName);
		Assert.areEqual(6, fields.size(), 'Expected 6 fields, found ' + fields);
		Assert.areEqual('1', fields[0].name);
		Assert.areEqual('1', fields[0].label);
		Assert.areEqual('A1', fields[0].exampleValue);

		Assert.areEqual('2', fields[1].name);
		Assert.areEqual('2', fields[1].label);
		Assert.areEqual('A2', fields[1].exampleValue);

		Assert.areEqual('3', fields[2].name);
		Assert.areEqual('3', fields[2].label);
		Assert.areEqual('A3', fields[2].exampleValue);

		Assert.areEqual('4', fields[3].name);
		Assert.areEqual('4', fields[3].label);
		Assert.areEqual('A4', fields[3].exampleValue);

		Assert.areEqual('5', fields[4].name);
		Assert.areEqual('5', fields[4].label);
		Assert.areEqual('A5', fields[4].exampleValue);

		Assert.areEqual('6', fields[5].name);
		Assert.areEqual('6', fields[5].label);
		Assert.areEqual('A6', fields[5].exampleValue);
	}

	@IsTest
	static void testGetObjectsForPath() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1719949</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);
		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=100&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8'),
			resp
		);

		ValenceS3Adapter.ListBucketResult results = ValenceS3Adapter.getObjectsForPath(
			namedCredential,
			ctx.linkSourceName,
			cfg.path,
			null
		);
		Assert.areEqual(2, results.CommonPrefixes.size());
		Assert.areEqual(cfg.path + 'nested1/', results.CommonPrefixes[0]);
		Assert.areEqual(cfg.path + 'nested2/', results.CommonPrefixes[1]);
	}

	//////////////
	// Planning //
	//////////////

	@IsTest
	static void testPlan() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1719949</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);

		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=100&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8'),
			resp
		);

		ValenceS3Adapter.ListBucketResult results = ValenceS3Adapter.getObjectsForPath(
			namedCredential,
			ctx.linkSourceName,
			cfg.path,
			null
		);
		Assert.areEqual(2, results.CommonPrefixes.size());
		Assert.areEqual(cfg.path + 'nested1/', results.CommonPrefixes[0]);
		Assert.areEqual(cfg.path + 'nested2/', results.CommonPrefixes[1]);
	}

	@IsTest
	static void testPlanFetch() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		cfg.mbsPerBatch = '0.1';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1048576</Size>' + // 1MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File2.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>524288</Size>' + // 0.5MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);
		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=25&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8'),
			resp
		);

		// mock get byte range of file
		resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody('1,2,3,4,5,6\nA1,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6\n');
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File1.csv', resp);
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File2.csv', resp);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		adapter.setSourceConfiguration(ctx, JSON.serialize(cfg));

		valence.FetchStrategy strat = adapter.planFetch(ctx);
		Assert.areEqual('CUMULATIVE_SCOPES', strat.checkStrategyType());
		Assert.areEqual(15, strat.checkScopeCount());
	}

	@IsTest
	static void testPlanFetchDelta() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ctx.lastSuccessfulSync = Datetime.now();
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		cfg.mbsPerBatch = '0.1';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1048576</Size>' + // 1MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File2.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>524288</Size>' + // 0.5MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);
		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=25&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8'),
			resp
		);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		adapter.setSourceConfiguration(ctx, JSON.serialize(cfg));

		valence.FetchStrategy strat = adapter.planFetch(ctx);
		Assert.areEqual('NO_RECORDS', strat.checkStrategyType());
	}

	@IsTest
	static void testPlanFetchAgain() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		cfg.mbsPerBatch = '0.1';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);
		// mock list objects
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody(
			'<?xml version="1.0" encoding="UTF-8"?>' +
				'<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/">' +
				'		<Name>' +
				ctx.linkSourceName +
				'</Name>' +
				'		<Prefix>' +
				cfg.path +
				'</Prefix>' +
				'		<KeyCount>1</KeyCount>' +
				'		<MaxKeys>1000</MaxKeys>' +
				'		<IsTruncated>false</IsTruncated>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>0</Size>' +
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File1.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>1048576</Size>' + // 1MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<Contents>' +
				'				<Key>' +
				cfg.path +
				'File2.csv</Key>' +
				'				<LastModified>2024-10-29T20:31:45.000Z</LastModified>' +
				'				<ETag>&quot;1a465974f1222f9872a2d3a9748347c3&quot;</ETag>' +
				'				<Size>524288</Size>' + // 0.5MB file size
				'				<StorageClass>STANDARD</StorageClass>' +
				'		</Contents>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested1/</Prefix>' +
				'		</CommonPrefixes>' +
				'		<CommonPrefixes>' +
				'			<Prefix>' +
				cfg.path +
				'nested2/</Prefix>' +
				'		</CommonPrefixes>' +
				'</ListBucketResult>'
		);
		mock.responseMap.put(
			'callout:' +
				namedCredential +
				'/' +
				ctx.linkSourceName +
				'/?list-type=2&delimiter=%2F&max-keys=25&prefix=' +
				EncodingUtil.urlEncode(cfg.path, 'UTF-8') +
				'&continuation-token=token123',
			resp
		);

		// mock get byte range of file
		resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody('1,2,3,4,5,6\nA1,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6\n');
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File1.csv', resp);
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File2.csv', resp);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		adapter.setSourceConfiguration(ctx, JSON.serialize(cfg));

		ValenceS3Adapter.Scope scp = new ValenceS3Adapter.Scope();
		scp.nextContinuationToken = 'token123';
		valence.FetchStrategy strat = adapter.planFetchAgain(ctx, scp);
		Assert.areEqual('CUMULATIVE_SCOPES', strat.checkStrategyType());
		Assert.areEqual(15, strat.checkScopeCount());
	}

	///////////////////
	// Fetch Records //
	///////////////////

	@IsTest
	static void testFetchRecords() {
		String namedCredential = 'TEST_CRED';
		valence.LinkContext ctx = new valence.LinkContext();
		ctx.linkSourceName = 'bucket-123';
		ValenceS3Adapter.Config cfg = new ValenceS3Adapter.Config();
		cfg.path = 'folder1/folder2/';
		cfg.mbsPerBatch = '0.1';
		MockCallout mock = new MockCallout();
		Test.setMock(HttpCalloutMock.class, mock);

		// mock get byte range of file
		HttpResponse resp = new HttpResponse();
		resp.setStatusCode(200);
		resp.setBody('1,2,3,4,5,6\nA1,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6\n');
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File1.csv', resp);
		mock.responseMap.put('callout:' + namedCredential + '/' + ctx.linkSourceName + '/' + cfg.path + 'File2.csv', resp);

		ValenceS3Adapter adapter = new ValenceS3Adapter();
		adapter.setNamedCredential(namedCredential);
		adapter.setSourceConfiguration(ctx, JSON.serialize(cfg));

		ValenceS3Adapter.Scope scp = new ValenceS3Adapter.Scope();
		scp.key = cfg.path + 'File1.csv';
		scp.totalBytes = 1000;
		scp.startBytes = 0;
		scp.endBytes = 500;
		List<valence.RecordInFlight> records = adapter.fetchRecords(ctx, scp);
		Assert.areEqual(2, records.size());
		Assert.areEqual(
			'A1',
			records[0].getOriginalPropertyValue('1'),
			'Actual original properties:' + records[0].getOriginalProperties()
		);
	}

	//////////////////////
	// CSV Parser Tests //
	//////////////////////

	static ValenceS3Adapter.CsvConfig csvCfg = new ValenceS3Adapter.CsvConfig();
	@IsTest
	static void testCsvIncrementalParser() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(
			Blob.valueOf(
				'1,2,3,4,5,6\n' +
					'A1,A2,A3,A4,A5,A6\n' +
					'B1,B2,B3,B4,B5,B6\n' +
					'C1,C2,C3,C4,C5,C6\n' +
					'D1,D2,D3,D4,D5,D6\n' +
					'E1,E2,E3,E'
			),
			false
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));

		csv.addContent(Blob.valueOf('4,E5,E6\n' + 'F1,F2,F3,F4,F5,F6\n' + 'G1,G2,G3,G4,G5,G'), false);
		expectedRows.clear();
		expectedRows.add(
			new Map<String, String>{ '1' => 'E1', '2' => 'E2', '3' => 'E3', '4' => 'E4', '5' => 'E5', '6' => 'E6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'F1', '2' => 'F2', '3' => 'F3', '4' => 'F4', '5' => 'F5', '6' => 'F6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));

		csv.addContent(Blob.valueOf('6\nH1,H2,H3,H4,H5,H6\n' + 'I1,I2,I3,I4,I5,I6'), true);

		expectedRows.clear();

		expectedRows.add(
			new Map<String, String>{ '1' => 'G1', '2' => 'G2', '3' => 'G3', '4' => 'G4', '5' => 'G5', '6' => 'G6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'H1', '2' => 'H2', '3' => 'H3', '4' => 'H4', '5' => 'H5', '6' => 'H6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'I1', '2' => 'I2', '3' => 'I3', '4' => 'I4', '5' => 'I5', '6' => 'I6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvWithCarriageReturns() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(
			Blob.valueOf(
				'1,2,3,4,5,6\r\n' +
					'A1,A2,A3,A4,A5,A6\r\n' +
					'B1,B2,B3,B4,B5,B6\r\n' +
					'C1,C2,C3,C4,C5,C6\r\n' +
					'D1,D2,D3,D4,D5,D6\r\n'
			),
			true
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvQuotes() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(
			Blob.valueOf(
				'1,2,3,4,5,6\r\n' +
					'"A""1",A2,A3,A4,A5,A6\r\n' +
					'B1,"""B2",B3,B4,B5,B6\r\n' +
					'C1,C2,"C3""",C4,C5,C6\r\n' +
					'D1,D2,D3,"""D""4""",D5,D6\r\n' +
					'E1,E2,E3,E4,"E,5",E6\r\n'
			),
			true
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A"1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => '"B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3"', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => '"D"4"', '5' => 'D5', '6' => 'D6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'E1', '2' => 'E2', '3' => 'E3', '4' => 'E4', '5' => 'E,5', '6' => 'E6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvFinalLine() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\n' + 'A1,A2,A3,A4,A5,A6\n'), false);
		csv.addContent(Blob.valueOf('B1,B2,B3,B4,B5,B6\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6\n'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	// pass in headers and a partial byte range, it should be able to find and keep the first x valid lines
	// ideally we can also gate the byte inclusion so we can tell it to ignore rows that are exclusively outside of the included bytes
	@IsTest
	static void testCsvStartWithHeaders() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(
			csvCfg,
			new List<String>{ '1', '2', '3', '4', '5', '6' },
			36
		);

		// skip 36 bytes
		// should result in a match during the C line
		csv.addContent(
			Blob.valueOf(',A4,A5,A6\n' + 'B1,B2,B3,B4,B5,B6\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6\n'),
			true
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvStartWithHeadersMidQuote() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(
			csvCfg,
			new List<String>{ '1', '2', '3', '4', '5', '6' },
			39
		);
		// should result in a match during the C line
		csv.addContent(
			Blob.valueOf('A3",A4,A5,A6\n' + 'B1,B2,B3,B4,B5,B6\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6\n'),
			true
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvStartMidQuotedSpecialChars() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(
			csvCfg,
			new List<String>{ '1', '2', '3', '4', '5', '6' },
			47
		);
		// should result in a match during the C line
		csv.addContent(
			Blob.valueOf('A2,\r\n,""A3",A4,A5,A6\n' + 'B1,B2,B3,B4,B5,B6\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6\n'),
			true
		);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'D1', '2' => 'D2', '3' => 'D3', '4' => 'D4', '5' => 'D5', '6' => 'D6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testCsvNonQuotingQuotes() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		// should result in a match during the C line
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\r\nA1,A2,A"31""A32",A4, "A5" ,A"6\n'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{
				'1' => 'A1',
				'2' => 'A2',
				'3' => 'A"31""A32"',
				'4' => 'A4',
				'5' => ' "A5" ',
				'6' => 'A"6'
			}
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	// TODO: Tests
	// PARSER
	// https://github.com/mholt/PapaParse/blob/master/tests/test-cases.js

	// non-quotes in partial read

	// do we support comments? "settings?"
	// treat empty as null?

	@IsTest
	static void testCompleteDanglingRowWithoutNewline() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(
			csvCfg,
			new List<String>{ '1', '2', '3', '4', '5', '6' },
			22
		);
		csv.addContent(Blob.valueOf('B1,B2,B3,B4,B5,B6\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6'), false);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testPartialThatOwnsNewlineShouldPullInBackRow() {
		String skippedData = 'A1,A2,A3,A4,A5,A6\n' + 'B1,B2,B3,B4,B5,B6';
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(
			csvCfg,
			new List<String>{ '1', '2', '3', '4', '5', '6' },
			skippedData.length()
		);
		csv.addContent(Blob.valueOf(skippedData + '\n' + 'C1,C2,C3,C4,C5,C6\n' + 'D1,D2,D3,D4,D5,D6'), false);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		// with the newline in scope it should pull forward the previous row
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'C1', '2' => 'C2', '3' => 'C3', '4' => 'C4', '5' => 'C5', '6' => 'C6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testEmptyFirstField() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\n,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => '', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testEmptyLastField() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\nA1,A2,A3,A4,A5,\nB1,B2,B3,B4,B5,B6'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => '' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testEmptyMiddleField() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\nA1,A2,A3,,A5,A6\nB1,B2,B3,B4,B5,B6'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => '', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testEmptyDoubleFields() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\nA1,A2,,,A5,A6\nB1,B2,B3,B4,,'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => '', '4' => '', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => '', '6' => '' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testWhitespaceOnEdge() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		csv.addContent(Blob.valueOf('1,2,3,4,5,6\nA1,  A2,A 3,A4  ,  A5,A6  \n  B1,"  B "" 2  ",B3,B4,,'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => '  A2', '3' => 'A 3', '4' => 'A4  ', '5' => '  A5', '6' => 'A6  ' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => '  B1', '2' => '  B " 2  ', '3' => 'B3', '4' => 'B4', '5' => '', '6' => '' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testPipeDelim() {
		ValenceS3Adapter.CsvConfig cfg = new ValenceS3Adapter.CsvConfig();
		cfg.delimiter = '|';

		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(cfg);
		csv.addContent(Blob.valueOf('1|2|3|4|5|6\nA1|A2|A3|A4|A5|A6\nB1|B2|B3|B4||'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => '', '6' => '' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testTabDelim() {
		ValenceS3Adapter.CsvConfig cfg = new ValenceS3Adapter.CsvConfig();
		cfg.delimiter = '\t';

		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(cfg);
		csv.addContent(Blob.valueOf('1\t2\t3\t4\t5\t6\nA1\tA2\tA3\tA4\tA5\tA6\nB1\tB2\tB3\tB4\t\t'), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => '', '6' => '' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	@IsTest
	static void testStartingBOM() {
		ValenceS3Adapter.CSVIncremental csv = new ValenceS3Adapter.CSVIncremental(csvCfg);
		String hexContent = 'dfbbbf'; // BOM
		hexContent += EncodingUtil.convertToHex(Blob.valueOf('1,2,3,4,5,6\nA1,A2,A3,A4,A5,A6\nB1,B2,B3,B4,B5,B6'));
		csv.addContent(EncodingUtil.convertFromHex(hexContent), true);

		List<Map<String, String>> expectedRows = new List<Map<String, String>>();
		expectedRows.add(
			new Map<String, String>{ '1' => 'A1', '2' => 'A2', '3' => 'A3', '4' => 'A4', '5' => 'A5', '6' => 'A6' }
		);
		expectedRows.add(
			new Map<String, String>{ '1' => 'B1', '2' => 'B2', '3' => 'B3', '4' => 'B4', '5' => 'B5', '6' => 'B6' }
		);
		Assert.isTrue(compareOutput(csv, expectedRows));
	}

	///////////////
	// UTILITIES //
	///////////////

	static Boolean compareOutput(ValenceS3Adapter.CSVIncremental csv, List<Map<String, String>> expectedRows) {
		for (Map<String, String> expectedRow : expectedRows) {
			System.debug(expectedRow);
			Map<String, String> actualRow = csv.next();
			System.debug(actualRow);
			Assert.areEqual(expectedRow.size(), actualRow.size());
			for (String expectedKey : expectedRow.keySet()) {
				Assert.isTrue(
					actualRow.containsKey(expectedKey),
					'Expect actual row to have key ' + expectedKey + ',' + actualRow
				);
				Assert.areEqual(expectedRow.get(expectedKey), actualRow.get(expectedKey));
			}
		}
		if (csv.hasNext()) {
			Assert.fail('Expected csv to have run out of records, next:' + csv.next());
		}
		return true;
	}

	class MockCallout implements HttpCalloutMock {
		List<HttpRequest> requests = new List<HttpRequest>();
		Map<String, HttpResponse> responseMap = new Map<String, HttpResponse>();
		public HTTPResponse respond(HTTPRequest req) {
			requests.add(req);
			if (responseMap.containsKey(req.getEndpoint())) {
				return responseMap.get(req.getEndpoint());
			}
			throw new MockCalloutException('Missing response for ' + req.getEndpoint());
		}
	}

	class MockCalloutException extends Exception {
	}
}