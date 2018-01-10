<template>
<div class="vue-select-wrapper">
<vue-select :multiple="multiple" v-model="selectedValues" :label="label" :placeholder="maketext('Search term...')" :options="options" :on-search="onSearchDebaunce" :get-option-label="getOptionLabel" :get-selected-option-label="getSelectedValuesLabel" :on-open="getOptions" :prevent-search-filter="true" :on-get-more-options="onGetMoreOptions">
    <template slot="more-results">{{maketext(moreResultsText)}}</template>
</vue-select>
</div>
</template>

<script>
/* global $ foswiki */
import debounce from 'lodash/debounce';
import MaketextMixin from './MaketextMixin.vue'
export default {
    mixins: [MaketextMixin],
    props: {
        multiple: {
            type: Boolean
        },
        user: {
            type: Boolean
        },
        group: {
            type: Boolean
        },
        label: {
            type: String,
            default: "name"
        }
    },
    data() {
        return {
            options: [],
            selectedValues: [],
            limit: 10,
            moreResultsText: "Show more results"
        }
    },
    components: {
        VueSelect
    },
    computed: {
        onSearchDebaunce(){
            return debounce(this.getOptions, 300);
        }
    },
    methods: {
        getOptions(search, loading, offset) {
            var params = {
                q: search,
                limit: this.limit,
                page: offset,
                group: this.group ? 1 : 0,
                user: this.user ? 1 : 0
            }
            if( typeof loading === "function"){
                loading(true);
            }
            $.getJSON(foswiki.getScriptUrl('rest', 'UnifiedAuthPlugin', 'users'), params)
            .done((result) => {
                if(result.length < this.limit ){
                    this.moreResultsText = this.maketext("No more results available");
                } else {
                    this.moreResultsText = this.maketext("Show more results");
                }
                this.setOptions(result, offset);
            })
            .always(() => {
                if( typeof loading === "function"){
                    loading(false);
                }
            });
        },
        setOptions(result, offset) {
            if(offset == 0 || offset === undefined){
                this.options = result;
            } else {
                this.options = this.options.concat(result);
            }

        },
        onSearch(search, loading) {
            this.getOptions(search, loading);
        },
        getOptionLabel(option){
            return option[this.label];
        },
        getSelectedValues() {
            return this.selectedValues;
        },
        getSelectedValuesLabel(option) {
            return option[this.label];
        },
        onGetMoreOptions(search, loading) {
            this.getOptions(search,loading, this.options.length);
        },
        clearSelectedValues(){
            this.selectedValues = null;
        }
    }
}
</script>
