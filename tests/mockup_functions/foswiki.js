window.foswiki = {
    preferences: {
        SCRIPTURL: "rest"
    },
  jsi18n: {
    get(){
      return "MT:" + [...arguments];
    }
  },
  getScriptUrl: function() {
    return "SCRIPTURL";
  },
  getPreference: function(pref) {
    return "PREF:"+pref;
  }
};
