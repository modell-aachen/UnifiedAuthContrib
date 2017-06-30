var baseConfig = require('./development.webpack.config.js');
var webpack = require('webpack');
var merge = require('webpack-merge');

module.exports = merge(baseConfig, {
	devtool: "inline-source-map",
	plugins: [
		new webpack.ProvidePlugin({
			$: "jquery",
			moment: "moment"
		})
	]
});