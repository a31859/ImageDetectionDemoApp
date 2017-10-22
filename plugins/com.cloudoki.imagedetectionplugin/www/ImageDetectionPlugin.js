/**
*
**/
var ImageDetectionPlugin = function () {};

ImageDetectionPlugin.prototype.startProcessing = function (bool, successCallback, errorCallback) {
  cordova.exec(successCallback, errorCallback, "ImageDetectionPlugin", "startProcessing", [bool, window.innerHeight, window.innerWidth]);
};
ImageDetectionPlugin.prototype.setPatterns = function (patterns, successCallback, errorCallback) {
 var _patterns = [];
 if (!(patterns instanceof Array)){
   _patterns.push(patterns);
 } else {
   _patterns = patterns;
 }
 cordova.exec(successCallback, errorCallback, "ImageDetectionPlugin", "setPatterns", _patterns);
};
ImageDetectionPlugin.prototype.isDetecting = function (successCallback, errorCallback) {
  cordova.exec(successCallback, errorCallback, "ImageDetectionPlugin", "isDetecting", []);
};
ImageDetectionPlugin.prototype.setDetectionTimeout = function (timeout, successCallback, errorCallback) {
  cordova.exec(successCallback, errorCallback, "ImageDetectionPlugin", "setDetectionTimeout", [timeout]);
};
ImageDetectionPlugin.prototype.greet = function (name, successCallback, errorCallback) {
  cordova.exec(successCallback, errorCallback, "ImageDetectionPlugin", "greet", [name]);
};

if (!window.plugins) {
  window.plugins = {};
}

if (!window.plugins.ImageDetectionPlugin) {
  window.plugins.ImageDetectionPlugin = new ImageDetectionPlugin();
}

if (typeof module != 'undefined' && module.exports){
  module.exports = ImageDetectionPlugin;
}
