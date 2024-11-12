/**
 * Custom UI for building configurations for the ValenceS3Adapter Filter.
 */
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

import ValenceUIConfigurator from 'c/valenceUIConfigurator';
import getObjectsForPath from '@salesforce/apex/ValenceS3Adapter.getObjectsForPath';

export default class S3AdapterConfigurator extends ValenceUIConfigurator {
	s3Tree = [];
	pathPrefix = '';
	nextContinuationToken;
	s3HasNext = false;
	loading = false;

	async onSetLink() {
		this.loading = true;
		const items = [];
		const newTree = [
			{
				label: `${this.link.sourceName} (bucket)`,
				name: '',
				items: items,
			},
		];
		// populate the tree
		await this.getS3Objects('', items);
		// new tree should be ready to go, assign it to the object to cause rendering
		this.s3Tree = newTree;
		this.loading = false;
	}

	// -----------------------------------------
	// ----- Required Configurator Methods -----
	// -----------------------------------------

	getDefaultShape() {
		return {
			path: '',
			maxObjectsPerPlan: undefined,
			bytesForHeaderFetch: undefined,
			bytesForFetchPrefix: undefined,
			mbsPerBatch: undefined,
			fieldSeparator: undefined,
			fileEnding: undefined,
		};
	}

	computeValid() {
		// nothing is required
		return true;
	}

	async getS3Objects(prefix, itemList, continuationToken) {
		try {
			const data = await getObjectsForPath({
				namedCredential: this.link.sourceNamedCredentialName,
				bucket: this.link.sourceName,
				prefix: prefix,
				continuation: continuationToken,
			});
			if (data.CommonPrefixes) {
				// CommonPrefixs is the "directories" inside of this one
				const promises = [];
				itemList.push(
					...data.CommonPrefixes.map((p) => {
						const items = [];
						// retrieve the directories on the levels below and make them part of the tree
						promises.push(this.getS3Objects(p, items));
						return {
							label: p.substring(prefix.length),
							name: p,
							items: items,
						};
					}),
				);
				// wait for all the async actions
				await Promise.all(promises);
			}
			this.nextContinuationToken = data.NextContinuationToken;
			if (data.Contents) {
				const file = data.Contents.find((c) => c.Size > 0);
				if (file) {
					// we believe that if we see a non-directory then we've collected all possible directories
					// at this level and don't need to iterate over the individual files
					// clearing this value breaks the loop
					data.NextContinuationToken = undefined;
				}
			}
			if (data.NextContinuationToken) {
				// need to get more data at this same level
				this.getS3Objects(prefix, itemList, data.NextContinuationToken);
			}
		} catch (error) {
			const evt = new ShowToastEvent({
				title: 'There was a problem',
				message: error,
				variant: 'error',
				mode: 'sticky',
			});
			this.dispatchEvent(evt);
		}
	}

	treeSelected(event) {
		this.configuration.path = event.detail.name;
		this.configUpdated();
	}
}
