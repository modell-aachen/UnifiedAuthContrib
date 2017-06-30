import Vue from 'vue';
import './mockup_functions/sidebar.js';
import './mockup_functions/foswiki.js';
import './mockup_functions/jquery.js';

Vue.config.productionTip = false;

export default {
  createVueComponent(componentDefinition, constructionOptions) {
    const Ctor = Vue.extend(componentDefinition);
    return new Ctor(constructionOptions);
  }
}
