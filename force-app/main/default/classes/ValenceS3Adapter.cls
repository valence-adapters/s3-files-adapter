global with sharing class ValenceS3Adapter implements valence.ConfigurableSourceAdapter, valence.DelayedPlanningAdapter, valence.NamedCredentialAdapter, valence.SchemaAdapter, valence.SourceAdapterForPull, valence.SourceAdapterScopeSerializer {
	// configurable
	private String configuredNamedCredential;
	private Config currentConfig;

	// BYTE ORDER MARK, sometimes begins UTF8 CSV content
	private static final String BOM = 'dfbbbf';

	public String getSourceConfigurationLightningComponent(valence.LinkContext ctx) {
		return 'c:s3AdapterConfigurator';
	}

	public String getSourceConfigurationStructure(valence.LinkContext ctx) {
		return null;
	}

	public String explainSourceConfiguration(valence.LinkContext ctx, String configString) {
		Config cfg = (Config) JSON.deserialize(configString, Config.class);

		// build rich text matching existing setting display patterns
		List<String> lines = new List<String>();
		lines.add('<dl class="slds-dl_horizontal slds-m-top_x-small" style="--lwc-fontWeightBold: 400;">');

		// describe how we'll target files
		String fileString = '';
		if (String.isBlank(cfg.path)) {
			fileString = 'All files in the root of the bucket';
		} else if (cfg.path.endsWith('/')) {
			fileString = String.format('All files in "{0}"', new List<String>{ cfg.path });
		} else {
			fileString = cfg.path;
		}
		lines.add(buildConfigRow('Source File(s)', fileString));

		// various settings
		if (String.isNotBlank(cfg.mbsPerBatch)) {
			lines.add(
				buildConfigRow(
					'Chunk Size',
					String.format('{0}MB', new List<String>{ cfg.getMaxMbytesToReady().stripTrailingZeros().toString() })
				)
			);
		}
		if (String.isNotBlank(cfg.fieldSeparator)) {
			lines.add(buildConfigRow('Break Fields On', String.format('"{0}"', new List<String>{ cfg.fieldSeparator })));
		}
		if (String.isNotBlank(cfg.maxObjectsPerPlan)) {
			lines.add(buildConfigRow('Scope Plan Count', cfg.maxObjectsPerPlan));
		}
		if (String.isNotBlank(cfg.bytesForFetchPrefix)) {
			lines.add(buildConfigRow('Prefetched Bytes', cfg.bytesForFetchPrefix));
		}
		if (String.isNotBlank(cfg.bytesForHeaderFetch)) {
			lines.add(buildConfigRow('Max Header Bytes', String.format('{0}', new List<String>{ cfg.bytesForHeaderFetch })));
		}

		lines.add('</dl>');

		return String.join(lines, '');
	}

	private String buildConfigRow(String label, String value) {
		return String.format(
			'<dt class="slds-dl_horizontal__label tweaked-text-title_caps slds-m-top_x-small slds-size_5-of-12">{0}:</dt>' +
			'<dd class="slds-dl_horizontal__detail slds-m-left_none slds-m-top_x-small slds-size_7-of-12">{1}</dd>',
			new List<String>{ label, value }
		);
	}

	public void setSourceConfiguration(valence.LinkContext ctx, String configString) {
		this.currentConfig = (Config) JSON.deserialize(configString, Config.class);
	}

	public void setNamedCredential(String namedCredentialName) {
		this.configuredNamedCredential = namedCredentialName;
	}

	public String serializeScope(Object scope) {
		return JSON.serialize(scope);
	}

	public Object deserializeScope(String scopeString) {
		return JSON.deserialize(scopeString, Scope.class);
	}

	// schema //

	// "tables" are S3 buckets
	public List<valence.Table> getTables() {
		// find all buckets for the inital configuration
		List<valence.Table> tables = new List<valence.Table>();

		for (ListBucketResultBucket bucket : getAllBuckets()) {
			tables.add(valence.Table.create(bucket.Name).withDescription('S3 Bucket').setReadable(true).build());
		}

		return tables;
	}

	// find a file that matches our target and get the headers and first row to discover fields
	public List<valence.Field> getFields(String tableApiName) {
		List<valence.Field> fields = new List<valence.Field>();
		// get the first CSV file matching the bucket & prefix values
		// we grab up to 100 because some returned values will be directories
		List<ListBucketResultContent> contents = getBucketContentsForPrefix(tableApiName, 100, this.currentConfig.path);
		for (ListBucketResultContent content : contents) {
			// this is probably a directory, keep looking
			if (content.Size == 0) {
				continue;
			}
			CSVIncremental csv = peekCsvFile(tableApiName, content);
			for (Map<String, String> row : csv) {
				for (String key : row.keySet()) {
					fields.add(
						valence.Field.create(key).withLabel(key).withType('string').withExampleValue(row.get(key)).build()
					);
				}
				break;
			}
			// found the first file, leaving the loop
			break;
		}

		return fields;
	}

	public valence.FetchStrategy planFetch(valence.LinkContext ctx) {
		return fetchAndBuildScopes(ctx, new Scope());
	}

	public valence.FetchStrategy planFetchAgain(valence.LinkContext ctx, Object scope) {
		return fetchAndBuildScopes(ctx, (Scope) scope);
	}

	private valence.FetchStrategy fetchAndBuildScopes(valence.LinkContext ctx, Scope scope) {
		// get the first X objects from S3
		ListBucketResult results = getS3ObjectList(
			ctx.linkSourceName,
			this.currentConfig.getMaxObjectsPerPlan(),
			this.currentConfig.path,
			scope.nextContinuationToken
		);
		// capture the continuation token so we can iterate through the list in subsequent `planFetchAgain`
		scope.nextContinuationToken = results.NextContinuationToken;

		List<Scope> scopes = new List<Scope>();
		if (results.Contents != null) {
			for (ListBucketResultContent s3Obj : results.Contents) {
				if (s3Obj.Key.substring((this.currentConfig.path ?? '').length()).contains('/')) {
					// in a subfolder, should be ignored
					continue;
				}
				// limit to non-empty files matching our expected suffix
				if (s3Obj.Size > 0) {
					// if this is a delta, use the last sync data against the LastModified on the file
					if (ctx.lastSuccessfulSync == null || ctx.lastSuccessfulSync < s3Obj.LastModified) {
						// look at the top of the file to get the headers then chunk the bytes into scopes
						scopes.addAll(buildScopesForObject(ctx.linkSourceName, s3Obj));
					}
				}
			}
		}
		// if there is no chance of more records and we didn't get anything useful
		if (results.IsTruncated == 'false' && scopes.isEmpty()) {
			return valence.FetchStrategy.noRecords();
		}

		// send out what scopes we have and if the list from S3 isn't empty yet then send the scope forward to cause a `planFetchAgain`
		return valence.FetchStrategy.cumulativeScopes(scopes, null, results.IsTruncated == 'true' ? scope : null);
	}

	/**
	 * given a scope of byte ranges, pull a portion of the CSV file and transform it into RecordsInFlight
	 * has special handling to ensure we look backward to gather a complete CSV row for which we might only have partial byte assignment
	 */
	public List<valence.RecordInFlight> fetchRecords(valence.LinkContext ctx, Object scopeObj) {
		Scope scope = (Scope) scopeObj;

		String url =
			'callout:' +
			configuredNamedCredential +
			'/' +
			EncodingUtil.urlEncode(ctx.linkSourceName, 'UTF-8') +
			'/' +
			cleanUrlPath(scope.key);

		Long startBytes = scope.startBytes;
		// cap the request to the total bytes for the file
		Long endBytes = scope.endBytes;
		// pad the front of the retrieved data so we can try and make sure we get a clean start row
		// the previous job is expected not process the final partial row so we have to
		Long actualStart = Math.max(0, startBytes - this.currentConfig.getBytesForFetchPrefix());
		Integer ignoredBytes = Integer.valueOf(startBytes - actualStart);
		HttpRequest req = new HttpRequest();
		req.setEndpoint(url);
		req.setMethod('GET');
		req.setHeader(
			'Range',
			String.format('bytes={0}-{1}', new List<String>{ String.valueOf(actualStart), String.valueOf(endBytes) })
		);
		HttpResponse res = new Http().send(req);
		if (res.getStatusCode() >= 400) {
			throw new valence.AdapterException('Problem retrieving contents of ' + url + ', ' + res.getBody());
		}
		CsvConfig csvCfg = new CsvConfig();
		csvCfg.delimiter = this.currentConfig.getFieldSeparator();
		CSVIncremental csvParser;
		if (scope.startBytes == 0) {
			// our assignment is the beginning of the file, don't pre-seed headers or provide a skip range
			csvParser = new CSVIncremental(csvCfg);
		} else {
			// we are jumping into the middle of a file, need to seed the headers and inform it of bytes that we included for the look behind but
			// if a given row exists exclusively in the ignored bytes then the row is discarded
			csvParser = new CSVIncremental(csvCfg, scope.headers, ignoredBytes);
		}
		// parse the CSV blob data, if our assignment is the end of the file then when we run out of bytes assume that completes the final row
		csvParser.addContent(res.getBodyAsBlob(), endBytes == scope.totalBytes);

		List<valence.RecordInFlight> records = new List<valence.RecordInFlight>();

		// iterate over records and create RecordInFlight instances from them
		for (Map<String, String> record : csvParser) {
			records.add(new valence.RecordInFlight(record));
		}

		return records;
	}

	/**
	 * List all buckets available to these Named Credentials, region is handled at the Named Credential level
	 */
	private List<ListBucketResultBucket> getAllBuckets() {
		List<ListBucketResultBucket> buckets = new List<ListBucketResultBucket>();

		ListAllMyBucketsResult listBucketsResult;
		do {
			HttpRequest req = new HttpRequest();
			String endpoint = 'callout:' + configuredNamedCredential;
			if (String.isNotBlank(listBucketsResult?.ContinuationToken)) {
				endpoint += '&continuation-token=' + EncodingUtil.urlEncode(listBucketsResult.ContinuationToken, 'UTF-8');
			}
			req.setEndpoint(endpoint);
			req.setMethod('GET');
			HttpResponse res = new Http().send(req);
			String body = res.getBody();
			if (res.getStatusCode() >= 400) {
				throw new valence.AdapterException('Failed to list S3 buckets:' + body);
			}

			DataWeave.Script dwscript = new DataWeaveScriptResource.S3ListAllMyBucketsResponseToJson();
			DataWeave.Result dwresult = dwscript.execute(new Map<String, Object>{ 'payload' => body });
			listBucketsResult = (ListAllMyBucketsResult) JSON.deserialize(
				(String) dwresult.getValue(),
				ListAllMyBucketsResult.class
			);

			List<Scope> scopes = new List<Scope>();
			if (listBucketsResult.Buckets != null) {
				for (ListBucketResultBucket bucket : listBucketsResult.Buckets) {
					buckets.add(bucket);
				}
			}
		} while (String.isNotBlank(listBucketsResult.ContinuationToken)); // see if we have more results to pull

		return buckets;
	}

	/**
	 * given a bucket find a max of {maxResults} items in that bucket, can be filtered to files, folders, or both and can be limited to objects with a specific prefix
	 */
	private List<ListBucketResultContent> getBucketContentsForPrefix(
		String bucketName,
		Integer maxResults,
		String prefix
	) {
		// this can be a huge performance problem, if the account has lots of buckets and those buckets have lots of files then we'll crash hard
		// not sure how to handle this incrementally, would be nice to have a lazy loading system and browser it like a file system
		List<ListBucketResultContent> contents = new List<ListBucketResultContent>();
		Integer filesChecked = 0;

		// ask S3 about the files currently in the bucket, optionally filter on the pathPrefix
		// continuation token caried forward between runs so we can fully drain the list
		String nextContinuationToken;
		do {
			// get list of items in the bucket
			ListBucketResult results = getS3ObjectList(bucketName, maxResults, prefix, nextContinuationToken);
			nextContinuationToken = results.NextContinuationToken;

			// respect selection preferences
			if (results.Contents != null) {
				for (ListBucketResultContent content : results.Contents) {
					// keep track of how many entries we've looked at, we'll bail if this number gets too high
					filesChecked++;
					if (content.Size == 0 && content.Key.endsWith('/')) {
						contents.add(content);
					}
					if (content.Size > 0) {
						contents.add(content);
					}
				}
			}

			// should have some way to notify the caller that we didn't finish iterating the bucket contents
			if (contents.size() >= maxResults) {
				break; // exit and send what we found
			}
			// hard cap on the number of bucket items we're willing to look through
		} while (filesChecked > 10000 && String.isNotBlank(nextContinuationToken));

		return contents;
	}

	/**
	 * perform the callout and data transformation to get the list of items in S3
	 * limited to a single folder level where that folder is the "prefix" param
	 */
	private ListBucketResult getS3ObjectList(
		String bucketName,
		Integer maxResults,
		String prefix,
		String continuationToken
	) {
		HttpRequest req = new HttpRequest();
		String endpoint =
			'callout:' +
			configuredNamedCredential +
			'/' +
			EncodingUtil.urlEncode(bucketName, 'UTF-8') +
			'/?list-type=2&delimiter=%2F';
		if (maxResults != null && maxResults > 0) {
			endpoint += '&max-keys=' + Math.min(1000, maxResults); // cap to 1000 elements in the results
		}
		if (String.isNotBlank(prefix)) {
			endpoint += '&prefix=' + EncodingUtil.urlEncode(prefix, 'UTF-8');
		}
		if (String.isNotBlank(continuationToken)) {
			endpoint += '&continuation-token=' + EncodingUtil.urlEncode(continuationToken, 'UTF-8');
		}
		req.setEndpoint(endpoint);
		req.setMethod('GET');
		HttpResponse res = new Http().send(req);
		String body = res.getBody();
		if (res.getStatusCode() >= 300) {
			throw new valence.AdapterException(
				'Failed to list objects in S3 bucket, status code: ' + res.getStatusCode() + ', Body:\n' + body
			);
		}

		try {
			DataWeave.Script dwscript = new DataWeaveScriptResource.S3ListBucketResponseToJson();
			DataWeave.Result dwresult = dwscript.execute(new Map<String, Object>{ 'payload' => body });
			return (ListBucketResult) JSON.deserialize((String) dwresult.getValue(), ListBucketResult.class);
		} catch (Exception e) {
			throw new valence.AdapterException(
				'Problem processing API response from S3 while listing objects, body:' + body,
				e
			);
		}
	}

	/**
	 * gets only the top of the file, ideally enough that we can see the headers and a few rows
	 * used to build the fields list as well as capturing headers before we chunk the CSV file into batch scopes
	 */
	private CSVIncremental peekCsvFile(String bucketName, ListBucketResultContent s3Obj) {
		Long startBytes = 0;

		String url =
			'callout:' +
			configuredNamedCredential +
			'/' +
			EncodingUtil.urlEncode(bucketName, 'UTF-8') +
			'/' +
			cleanUrlPath(s3Obj.Key);
		// get the start of the file so we can get the column headers
		Long endBytes = Math.min(s3Obj.Size, this.currentConfig.getBytesForHeaderFetch());
		HttpRequest req = new HttpRequest();
		req.setEndpoint(url);
		req.setMethod('GET');
		req.setHeader('Range', String.format('bytes={0}-{1}', new List<String>{ '0', String.valueOf(endBytes) }));
		HttpResponse res = new Http().send(req);
		if (res.getStatusCode() >= 400) {
			throw new valence.AdapterException('Problem retrieving contents of ' + url + ', ' + res.getBody());
		}

		// start CSV processing the file so we can take the header row
		CsvConfig csvCfg = new CsvConfig();
		csvCfg.delimiter = this.currentConfig.getFieldSeparator();
		CSVIncremental csv = new CSVIncremental(csvCfg);
		csv.addContent(res.getBodyAsBlob(), endBytes == s3Obj.Size);
		return csv;
	}

	/**
	 * given an S3 item in a particular bucket, capture the headers and build scope objects with assigned byte ranges
	 */
	private List<Scope> buildScopesForObject(String bucketName, ListBucketResultContent s3Obj) {
		Long startBytes = 0;

		// start CSV processing the file so we can take the header row
		CSVIncremental csv = peekCsvFile(bucketName, s3Obj);
		// csv.addContent(res.getBodyAsBlob(), endBytes == s3Obj.Size);
		List<Scope> scopes = new List<Scope>();
		// build scope chunks for the file so we can run in parallel
		while (startBytes < s3Obj.Size) {
			// create an assigned "chunk"
			Scope s = new Scope();
			s.key = s3Obj.Key; // which file
			s.startBytes = startBytes; // where to start
			s.endBytes = Math.min(s3Obj.Size, startBytes + this.currentConfig.getMaxBytesToRead()); // where to end (truncate to end of file)
			s.totalBytes = s3Obj.Size; // total size of the file
			s.headers = csv.headers; // CSV headers because we won't have them when we pull chunks
			scopes.add(s);
			startBytes = s.endBytes + 1; // set the new start position for a possible next scope
		}

		return scopes;
	}

	private String cleanUrlPath(String url) {
		return url.replaceAll(' ', '%20');
	}

	/****************************/
	/* ADAPTER CLASS STRUCTURES */
	/****************************/

	// Scopes
	public class Scope {
		// plan
		public String nextContinuationToken;

		// batch
		public String key;
		public List<String> headers;
		public Long startBytes;
		public Long endBytes;
		public Long totalBytes;
	}

	// config structure and convenience methods
	public class Config {
		public String path;

		public String maxObjectsPerPlan;
		public String bytesForHeaderFetch;
		public String bytesForFetchPrefix;
		public String mbsPerBatch;
		public String fieldSeparator;

		private Decimal getMaxMbytesToReady() {
			if (String.isBlank(mbsPerBatch)) {
				return 1.0;
			}

			return Decimal.valueOf(mbsPerBatch);
		}

		public Integer getMaxBytesToRead() {
			// convert megabytes to bytes
			return (getMaxMbytesToReady() * 1024 * 1024).intValue();
		}

		public Integer getBytesForHeaderFetch() {
			if (String.isBlank(bytesForHeaderFetch)) {
				return 5000;
			}
			return Integer.valueOf(bytesForHeaderFetch);
		}

		public Integer getBytesForFetchPrefix() {
			if (String.isBlank(bytesForFetchPrefix)) {
				return 10000;
			}
			return Integer.valueOf(bytesForFetchPrefix);
		}

		public Integer getMaxObjectsPerPlan() {
			if (String.isBlank(maxObjectsPerPlan)) {
				return 25;
			}
			return Integer.valueOf(maxObjectsPerPlan);
		}

		public String getFieldSeparator() {
			return String.isBlank(fieldSeparator) ? ',' : fieldSeparator;
		}
	}

	/**********************/
	/* INCREMENTAL PARSER */
	/**********************/

	/**
	 * a class pattern to simulate a streaming parser
	 * can add content incrementally as it is available
	 * can act as an iterator, will drain records instead of leaving the main collection intact
	 **/
	public abstract class ParserIncremental implements Iterator<Map<String, String>>, Iterable<Map<String, String>> {
		private String partialRow = '';

		public void addContent(Blob content, Boolean isLast) {
			// prepend the previous tail of the partialRow to the beginning on the new content
			String newContent = this.partialRow + EncodingUtil.convertToHex(content);

			// consume some of the data and ask us to hold onto the remaainder
			this.partialRow = consumeUsableContent(newContent, isLast);
		}

		// we give you a string, you consume as much as you can, give me back the rest
		abstract String consumeUsableContent(String hexContent, Boolean isLast);
		//
		abstract List<Map<String, String>> getRecords();
		abstract Map<String, String> drainNextRecord();

		public System.Iterator<Map<String, String>> iterator() {
			return this;
		}

		public Boolean hasNext() {
			return !getRecords().isEmpty();
		}

		public Map<String, String> next() {
			if (hasNext()) {
				return drainNextRecord();
			} else {
				throw new NoSuchElementException('Iterator has no more elements.');
			}
		}
	}

	public class CsvConfig {
		public String delimiter = ',';
		public String quoteChar = '"';
		public String escapeChar = '"';
	}

	/**
	 * Incremental CSV Parser that allows you to deliver the CSV content in chunks
	 */
	public class CSVIncremental extends ParserIncremental {
		private CsvConfig config;
		private List<Map<String, String>> rows = new List<Map<String, String>>();
		// if headers are empty when the first data is added, headers will be assigned as the first row
		private List<String> headers;
		// ignored bytes, if a row is entirely contained in these bytes then it is ignored
		private Integer skipBytes = 0;
		// initialize to "unknown" so we can decide later, important for jumping into the middle of a file
		Boolean inQuotes = null;

		/**
		 * initialize a new parser that will read from the top of the file down
		 */
		public CSVIncremental(CsvConfig config) {
			this.config = config;
			inQuotes = false; // can initialize because we're at the beginning of the file
		}

		/**
		 * initialize a new parser that will start in the middle of a file
		 * file headers are provided to start because they aren't expected to be in our readable scope
		 * skipBytes is the number of bytes that we're adding as a "look behind"
		 * any CSV rows entirely contained in the first `skipBytes` of data are excluded from results
		 * if a row has partial content after the `skipBytes` watermark then it will be included in the output
		 */
		public CSVIncremental(CsvConfig config, List<String> headers, Integer skipBytes) {
			this.config = config;
			this.headers = headers;
			this.skipBytes = skipBytes;
		}

		/**
		 * utility method to merge headers with a new row
		 */
		public Map<String, String> convertToMap(List<String> row) {
			Map<String, String> mappedRow = new Map<String, String>();
			// for each entry in Headers, put the pair of data into a map
			for (Integer i = 0, l = headers.size(), rl = row.size(); i < l && i < rl; i++) {
				mappedRow.put(headers.get(i), row.get(i));
			}
			return mappedRow;
		}

		/**
		 * takes a string of hex characters, this consumes as much as it can, gives back the remainder
		 * isLast is a hint for last row handling
		 **/
		public override String consumeUsableContent(String hexContent, Boolean isLast) {
			partialRow = '';
			Boolean isFinished = false;
			Integer startPos = 0;
			// number of characters it takes to form a hex value
			final Integer CHUNK_SIZE = 2;
			final String delimiter = EncodingUtil.convertToHex(Blob.valueOf(this.config.delimiter));
			final String quoteChar = EncodingUtil.convertToHex(Blob.valueOf(this.config.quoteChar));
			final String escapeChar = EncodingUtil.convertToHex(Blob.valueOf(this.config.escapeChar));
			final List<String> unquoteHints = new List<String>{ delimiter, '0d', '0a' };

			// if necessary, trim off the leading BOM
			if (hexContent.startsWith(BOM)) {
				hexContent = hexContent.substring(BOM.length());
			}

			// iterate through hex, on non-quoted newlines spit out a row chunk
			// once we've iterated through all the characters and not run into a newline
			// whatever is left is our partial row, unless "isLast"

			// built up over the entire data set
			List<List<String>> csvRows = new List<List<String>>();
			// built up over a single row
			List<String> rowValues = new List<String>();
			// built up over a rows individual field
			List<String> values = new List<String>();
			for (Integer i = 0, l = hexContent.length(); i < l; i += CHUNK_SIZE) {
				// step through the hex pairs two at a time
				String character = hexContent.substring(i, i + CHUNK_SIZE);
				if (character == quoteChar) {
					// default to nothing special, we'll update the value if we still have content ahead
					String peekChar = '';
					if (hexContent.length() >= i + (CHUNK_SIZE * 2)) {
						// we haven't yet reached the end of our input, we can peek at the next character
						peekChar = hexContent.substring(i + CHUNK_SIZE, i + (CHUNK_SIZE * 2));
					}
					// if inQuotes in null then we jumped in mid file
					// need to look at the situation and guess at what this quote means
					// TODO: escape char is not necessarilly quote char

					if (inQuotes == null) {
						if (peekChar == quoteChar || unquoteHints.contains(peekChar)) {
							// this `"` is followed by one of " , \r or \n and suggests we started inside a quoted field
							// any "fields" we've found so far are actually part of the quoted field
							// clear all of our progress and revert to all of this being a single field
							rowValues.clear();
							csvRows.clear();
							inQuotes = true; // setting it to true will allow the normal handling to close it
							values.add(hexContent.substring(0, i)); // reset stored value to all characters preceeding the `"`
						} else {
							// this is probably starting a quoted block, will set isQuotes so normal flow can take over
							// if this is the start of a quoted field then we probably haven't done anything wrong yet
							inQuotes = false;
						}
					}
					if (inQuotes) {
						if (peekChar == quoteChar) {
							// this is an escaped double quote
							// increase the pointer to skip the peeked character
							i += CHUNK_SIZE;
							// inside of quotes double-double-quotes = a single `"` in the output
							values.add(character);
						} else if (unquoteHints.contains(peekChar)) {
							inQuotes = false;
						} else {
							// TODO: problem state, invalid quoteChar
						}
					} else if (values.isEmpty()) {
						// this quoteChar starts a value, should treat it as quoted
						inQuotes = true;
					} else {
						// non-special character
						values.add(character);
					}
				} else if (character == delimiter) {
					if (inQuotes == true) {
						values.add(character);
					} else {
						rowValues.add(EncodingUtil.convertFromHex(String.join(values, '')).toString());
						values.clear();
					}
				} else if (character == '0d') {
					if (inQuotes == true) {
						values.add(character);
					}
					// if not in quotes then discard it
				} else if (character == '0a') {
					if (inQuotes == true) {
						values.add(character);
						break;
					}
					// when we encounter a "\n" or end of line and !inQuotes then call that the completion of the line
					rowValues.add(EncodingUtil.convertFromHex(String.join(values, '')).toString());
					values.clear();
					// only includes rows that contain at least some content in our accepted range
					if ((i / CHUNK_SIZE) >= skipBytes) {
						csvRows.add(rowValues);
					}
					// reset the row aggregator
					rowValues = new List<String>();
					// bump the starting position
					startPos = i + 2;
				} else {
					// not special, just add it to the bundle
					values.add(character);
				}
			}
			// if last then drain the data, assume a complete row
			// otherwise data is left waiting for the next Blob to arrive
			if (isLast) {
				if (!rowValues.isEmpty()) {
					rowValues.add(EncodingUtil.convertFromHex(String.join(values, '')).toString());
					csvRows.add(rowValues);
				}
			}
			if (this.headers == null) {
				this.headers = csvRows.remove(0);
			}
			for (List<String> row : csvRows) {
				this.rows.add(convertToMap(row));
			}
			// send back remainder for another day
			return isLast ? '' : hexContent.substring(startPos);
		}

		public override List<Map<String, String>> getRecords() {
			return rows;
		}

		public override Map<String, String> drainNextRecord() {
			return rows.remove(0);
		}
	}

	/***********************/
	/* S3 Response Classes */
	/***********************/

	// S3 ListObjectsv2 response classes
	// https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListObjectsV2.html
	public class ListBucketResult {
		@AuraEnabled
		public String Name;
		@AuraEnabled
		public String prefix;
		@AuraEnabled
		public Integer KeyCount;
		@AuraEnabled
		public Integer MaxKeys;
		@AuraEnabled
		public String IsTruncated;
		@AuraEnabled
		public String ContinuationToken;
		@AuraEnabled
		public String NextContinuationToken;
		@AuraEnabled
		public List<ListBucketResultContent> Contents;
		@AuraEnabled
		public List<String> CommonPrefixes;
	}

	public class ListBucketResultContent {
		@AuraEnabled
		public String Key;
		@AuraEnabled
		public Datetime LastModified;
		@AuraEnabled
		public String ETag;
		@AuraEnabled
		public Long Size;
		@AuraEnabled
		public String StorageClass;
	}

	// S3 ListBuckets response classes
	// https://docs.aws.amazon.com/AmazonS3/latest/API/API_ListBuckets.html
	public class ListAllMyBucketsResult {
		public String ContinuationToken;
		public List<ListBucketResultBucket> Buckets;
	}

	public class ListBucketResultBucket {
		public String Name;
		public Datetime CreationDate;
	}

	/********************/
	/* LWC Configurator */
	/********************/
	@AuraEnabled
	public static ListBucketResult getObjectsForPath(
		String namedCredential,
		String bucket,
		String prefix,
		String continuation
	) {
		try {
			ValenceS3Adapter adapter = new ValenceS3Adapter();
			adapter.setNamedCredential(namedCredential);
			return adapter.getS3ObjectList(bucket, 100, prefix, continuation);
		} catch (Exception e) {
			throw new AuraHandledException(e.getMessage());
		}
	}
}