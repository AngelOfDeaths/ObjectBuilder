/*
*  Copyright (c) 2014-2017 Object Builder <https://github.com/ottools/ObjectBuilder>
*
*  Permission is hereby granted, free of charge, to any person obtaining a copy
*  of this software and associated documentation files (the "Software"), to deal
*  in the Software without restriction, including without limitation the rights
*  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
*  copies of the Software, and to permit persons to whom the Software is
*  furnished to do so, subject to the following conditions:
*
*  The above copyright notice and this permission notice shall be included in
*  all copies or substantial portions of the Software.
*
*  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
*  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
*  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
*  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
*  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
*  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
*  THE SOFTWARE.
*/

package
{
    import flash.display.BitmapData;
    import flash.display.Sprite;
    import flash.events.ErrorEvent;
    import flash.events.Event;
    import flash.filesystem.File;
    import flash.geom.Rectangle;
    import flash.net.registerClassAlias;
    import flash.utils.ByteArray;

    import mx.resources.ResourceManager;

    import nail.commands.Command;
    import nail.commands.Communicator;
    import nail.commands.ICommunicator;
    import nail.errors.NullArgumentError;
    import nail.errors.NullOrEmptyArgumentError;
    import nail.image.ImageCodec;
    import nail.image.ImageFormat;
    import nail.logging.Log;
    import nail.utils.FileUtil;
    import nail.utils.SaveHelper;
    import nail.utils.StringUtil;
    import nail.utils.VectorUtils;
    import nail.utils.isNullOrEmpty;

    import ob.commands.FindResultCommand;
    import ob.commands.HideProgressBarCommand;
    import ob.commands.LoadVersionsCommand;
    import ob.commands.NeedToReloadCommand;
    import ob.commands.ProgressBarID;
    import ob.commands.ProgressCommand;
    import ob.commands.SetClientInfoCommand;
    import ob.commands.SettingsCommand;
    import ob.commands.ShowProgressBarCommand;
    import ob.commands.files.CompileAsCommand;
    import ob.commands.files.CompileCommand;
    import ob.commands.files.CreateNewFilesCommand;
    import ob.commands.files.LoadFilesCommand;
    import ob.commands.files.UnloadFilesCommand;
    import ob.commands.sprites.ExportSpritesCommand;
    import ob.commands.sprites.FindSpritesCommand;
    import ob.commands.sprites.GetSpriteListCommand;
    import ob.commands.sprites.ImportSpritesCommand;
    import ob.commands.sprites.ImportSpritesFromFileCommand;
    import ob.commands.sprites.NewSpriteCommand;
    import ob.commands.sprites.OptimizeSpritesCommand;
    import ob.commands.sprites.OptimizeSpritesResultCommand;
    import ob.commands.sprites.RemoveSpritesCommand;
    import ob.commands.sprites.ReplaceSpritesCommand;
    import ob.commands.sprites.ReplaceSpritesFromFilesCommand;
    import ob.commands.sprites.SetSpriteListCommand;
    import ob.commands.things.DuplicateThingCommand;
    import ob.commands.things.ExportThingCommand;
    import ob.commands.things.FindThingCommand;
    import ob.commands.things.GetThingCommand;
    import ob.commands.things.GetThingListCommand;
    import ob.commands.things.ImportThingsCommand;
    import ob.commands.things.ImportThingsFromFilesCommand;
    import ob.commands.things.NewThingCommand;
    import ob.commands.things.RemoveThingCommand;
    import ob.commands.things.ReplaceThingsCommand;
    import ob.commands.things.ReplaceThingsFromFilesCommand;
    import ob.commands.things.SetThingDataCommand;
    import ob.commands.things.SetThingListCommand;
    import ob.commands.things.UpdateThingCommand;
    import ob.settings.ObjectBuilderSettings;
    import ob.utils.ObUtils;
    import ob.utils.SpritesFinder;
    import ob.utils.SpritesOptimizer;

    import otlib.animation.FrameDuration;
    import otlib.core.Version;
    import otlib.core.VersionStorage;
    import otlib.events.ProgressEvent;
    import otlib.events.StorageEvent;
    import otlib.loaders.PathHelper;
    import otlib.loaders.SpriteDataLoader;
    import otlib.loaders.ThingDataLoader;
    import otlib.obd.OBDEncoder;
    import otlib.obd.OBDVersions;
    import otlib.resources.Resources;
    import otlib.sprites.Sprite;
    import otlib.sprites.SpriteData;
    import otlib.sprites.SpriteStorage;
    import otlib.things.ThingCategory;
    import otlib.things.ThingData;
    import otlib.things.ThingProperty;
    import otlib.things.ThingType;
    import otlib.things.ThingTypeStorage;
    import otlib.utils.ChangeResult;
    import otlib.utils.ClientInfo;
    import otlib.utils.OTFI;
    import otlib.utils.OTFormat;
    import otlib.utils.ThingListItem;

    [ResourceBundle("strings")]

    public class ObjectBuilderWorker extends flash.display.Sprite
    {
        //--------------------------------------------------------------------------
        // PROPERTIES
        //--------------------------------------------------------------------------

        private var _communicator:ICommunicator;
        private var _things:ThingTypeStorage;
        private var _sprites:SpriteStorage;
        private var _datFile:File;
        private var _sprFile:File;
        private var _version:Version;
        private var _extended:Boolean;
        private var _transparency:Boolean;
        private var _improvedAnimations:Boolean;
        private var _errorMessage:String;
        private var _compiled:Boolean;
        private var _isTemporary:Boolean;
        private var _thingListAmount:uint;
        private var _spriteListAmount:uint;

        //--------------------------------------
        // Getters / Setters
        //--------------------------------------

        public function get clientChanged():Boolean
        {
            return ((_things && _things.changed) || (_sprites && _sprites.changed));
        }

        public function get clientIsTemporary():Boolean
        {
            return (_things && _things.isTemporary && _sprites && _sprites.isTemporary);
        }

        public function get clientLoaded():Boolean
        {
            return (_things && _things.loaded && _sprites && _sprites.loaded);
        }

        //--------------------------------------------------------------------------
        // CONSTRUCTOR
        //--------------------------------------------------------------------------

        public function ObjectBuilderWorker()
        {
            super();

            Resources.manager = ResourceManager.getInstance();

            _communicator = new Communicator();
            _thingListAmount = 100;
            _spriteListAmount = 100;

            register();
        }

        //--------------------------------------------------------------------------
        // METHODS
        //--------------------------------------------------------------------------

        //--------------------------------------
        // Public
        //--------------------------------------

        public function onGetThing(id:uint, category:String):void
        {
            sendThingData(id, category);
        }

        public function onCompile():void
        {
            this.onCompileAs(_datFile.nativePath,
                            _sprFile.nativePath,
                            _version,
                            _extended,
                            _transparency,
                            _improvedAnimations);
        }

        public function setSelectedThingIds(value:Vector.<uint>, category:String):void
        {
            if (value && value.length > 0) {
                if (value.length > 1) value.sort(Array.NUMERIC | Array.DESCENDING);
                var max:uint = _things.getMaxId(category);
                if (value[0] > max) {
                    value = Vector.<uint>([max]);
                }
                this.onGetThing(value[0], category);
                this.sendThingList(value, category);
            }
        }

        public function setSelectedSpriteIds(value:Vector.<uint>):void
        {
            if (value && value.length > 0) {
                if (value.length > 1) value.sort(Array.NUMERIC | Array.DESCENDING);
                if (value[0] > _sprites.spritesCount) {
                    value = Vector.<uint>([_sprites.spritesCount]);
                }
                this.sendSpriteList(value);
            }
        }

        public function sendCommand(command:Command):void
        {
            _communicator.sendCommand(command);
        }

        //--------------------------------------
        // Override Protected
        //--------------------------------------

        public function register():void
        {
            // Register classes.
            registerClassAlias("ObjectBuilderSettings", ObjectBuilderSettings);
            registerClassAlias("Version", Version);
            registerClassAlias("ClientInfo", ClientInfo);
            registerClassAlias("ThingType", ThingType);
            registerClassAlias("ThingData", ThingData);
            registerClassAlias("ThingProperty", ThingProperty);
            registerClassAlias("ThingListItem", ThingListItem);
            registerClassAlias("SpriteData", SpriteData);
            registerClassAlias("ByteArray", ByteArray);
            registerClassAlias("PathHelper", PathHelper);
            registerClassAlias("FrameDuration", FrameDuration);

            _communicator.registerCallback(SettingsCommand, onSettings);

            _communicator.registerCallback(LoadVersionsCommand, onLoadClientVersions);

            // File commands
            _communicator.registerCallback(CreateNewFilesCommand, onCreateNewFiles);
            _communicator.registerCallback(LoadFilesCommand, onLoadFiles);
            _communicator.registerCallback(CompileCommand, onCompile);
            _communicator.registerCallback(CompileAsCommand, onCompileAs);
            _communicator.registerCallback(UnloadFilesCommand, onUnloadFiles);

            // Thing commands
            _communicator.registerCallback(NewThingCommand, onNewThing);
            _communicator.registerCallback(UpdateThingCommand, onUpdateThing);
            _communicator.registerCallback(ImportThingsCommand, onImportThings);
            _communicator.registerCallback(ImportThingsFromFilesCommand, onImportThingsFromFiles);
            _communicator.registerCallback(ExportThingCommand, onExportThing);
            _communicator.registerCallback(ReplaceThingsCommand, onReplaceThings);
            _communicator.registerCallback(ReplaceThingsFromFilesCommand, onReplaceThingsFromFiles);
            _communicator.registerCallback(DuplicateThingCommand, onDuplicateThing);
            _communicator.registerCallback(RemoveThingCommand, onRemoveThings);
            _communicator.registerCallback(GetThingCommand, onGetThing);
            _communicator.registerCallback(GetThingListCommand, onGetThingList);
            _communicator.registerCallback(FindThingCommand, onFindThing);

            // Sprite commands
            _communicator.registerCallback(NewSpriteCommand, onNewSprite);
            _communicator.registerCallback(ImportSpritesCommand, onAddSprites);
            _communicator.registerCallback(ImportSpritesFromFileCommand, onImportSpritesFromFiles);
            _communicator.registerCallback(ExportSpritesCommand, onExportSprites);
            _communicator.registerCallback(ReplaceSpritesCommand, onReplaceSprites);
            _communicator.registerCallback(ReplaceSpritesFromFilesCommand, onReplaceSpritesFromFiles);
            _communicator.registerCallback(RemoveSpritesCommand, onRemoveSprites);
            _communicator.registerCallback(GetSpriteListCommand, onGetSpriteList);
            _communicator.registerCallback(FindSpritesCommand, onFindSprites);
            _communicator.registerCallback(OptimizeSpritesCommand, onOptimizeSprites);

            // General commands
            _communicator.registerCallback(NeedToReloadCommand, onNeedToReload);
        }

        //--------------------------------------
        // Private
        //--------------------------------------

        private function onLoadClientVersions(path:String):void
        {
            if (isNullOrEmpty(path))
                throw new NullOrEmptyArgumentError("path");

            VersionStorage.getInstance().load( new File(path) );
        }

        private function onSettings(settings:ObjectBuilderSettings):void
        {
            if (isNullOrEmpty(settings))
                throw new NullOrEmptyArgumentError("settings");

            Resources.locale = settings.getLanguage()[0];
            _thingListAmount = settings.objectsListAmount;
            _spriteListAmount = settings.spritesListAmount;
        }

        private function onCreateNewFiles(datSignature:uint,
                                          sprSignature:uint,
                                          extended:Boolean,
                                          transparency:Boolean,
                                          improvedAninations:Boolean):void
        {
            this.onUnloadFiles();

            _version = VersionStorage.getInstance().getBySignatures(datSignature, sprSignature);
            _extended = (extended || _version.value >= 960);
            _transparency = transparency;
            _improvedAnimations = (improvedAninations || _version.value >= 1050);

            this.createStorage();

            // Create things.
            _things.createNew(_version, _extended, _improvedAnimations);

            // Create sprites.
            _sprites.createNew(_version, _extended, _transparency)

            // Update preview.
            var thing:ThingType = _things.getItemType(ThingTypeStorage.MIN_ITEM_ID);
            this.onGetThing(thing.id, thing.category);

            // Send sprites.
            this.sendSpriteList(Vector.<uint>([1]));
        }

        private function createStorage():void
        {
            _things = new ThingTypeStorage();
            _things.addEventListener(StorageEvent.LOAD, storageLoadHandler);
            _things.addEventListener(StorageEvent.CHANGE, storageChangeHandler);
            _things.addEventListener(ProgressEvent.PROGRESS, thingsProgressHandler);
            _things.addEventListener(ErrorEvent.ERROR, thingsErrorHandler);

            _sprites = new SpriteStorage();
            _sprites.addEventListener(StorageEvent.LOAD, storageLoadHandler);
            _sprites.addEventListener(StorageEvent.CHANGE, storageChangeHandler);
            _sprites.addEventListener(ProgressEvent.PROGRESS, spritesProgressHandler);
            _sprites.addEventListener(ErrorEvent.ERROR, spritesErrorHandler);
        }

        private function onLoadFiles(datPath:String,
                                     sprPath:String,
                                     version:Version,
                                     extended:Boolean,
                                     transparency:Boolean,
                                     improvedAnimations:Boolean):void
        {
            if (isNullOrEmpty(datPath))
                throw new NullOrEmptyArgumentError("datPath");

            if (isNullOrEmpty(sprPath))
                throw new NullOrEmptyArgumentError("sprPath");

            if (!version)
                throw new NullArgumentError("version");

            this.onUnloadFiles();

            _datFile = new File(datPath);
            _sprFile = new File(sprPath);
            _version = version;
            _extended = (extended || _version.value >= 960);
            _transparency = transparency;
            _improvedAnimations = (improvedAnimations || _version.value >= 1050);

            var title:String = Resources.getString("loading");
            sendCommand(new ShowProgressBarCommand(ProgressBarID.DAT_SPR, title));

            createStorage();

            _things.load(_datFile, _version, _extended, _improvedAnimations);
            _sprites.load(_sprFile, _version, _extended, _transparency);
        }

        private function onCompileAs(datPath:String,
                                     sprPath:String,
                                     version:Version,
                                     extended:Boolean,
                                     transparency:Boolean,
                                     improvedAnimations:Boolean):void
        {
            if (isNullOrEmpty(datPath))
                throw new NullOrEmptyArgumentError("datPath");

            if (isNullOrEmpty(sprPath))
                throw new NullOrEmptyArgumentError("sprPath");

            if (!version)
                throw new NullArgumentError("version");

            if (!_things || !_things.loaded)
                throw new Error(Resources.getString("metadataNotLoaded"));

            if (!_sprites || !_sprites.loaded)
                throw new Error(Resources.getString("spritesNotLoaded"));

            var dat:File = new File(datPath);
            var spr:File = new File(sprPath);
            var structureChanged:Boolean = (_extended != extended ||
                                            _transparency != transparency ||
                                            _improvedAnimations != improvedAnimations);
            var title:String = Resources.getString("compiling");

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DAT_SPR, title));

            if (!_things.compile(dat, version, extended, improvedAnimations) ||
                !_sprites.compile(spr, version, extended, transparency)) {
                return;
            }

            // Save .otfi file
            var dir:File = FileUtil.getDirectory(dat);
            var otfiFile:File = dir.resolvePath(FileUtil.getName(dat) + ".otfi");
            var otfi:OTFI = new OTFI(extended, transparency, improvedAnimations);
            otfi.save(otfiFile);

            clientCompileComplete();

            if (!_datFile || !_sprFile) {
                _datFile = dat;
                _sprFile = spr;
            }

            // If extended or alpha channel was changed need to reload.
            if (FileUtil.equals(dat, _datFile) && FileUtil.equals(spr, _sprFile)) {
                if (structureChanged)
                    sendCommand(new NeedToReloadCommand(extended, transparency, improvedAnimations));
                else
                    sendClientInfo();
            }
        }

        private function onUnloadFiles():void
        {
            if (_things) {
                _things.unload();
                _things.removeEventListener(StorageEvent.LOAD, storageLoadHandler);
                _things.removeEventListener(StorageEvent.CHANGE, storageChangeHandler);
                _things.removeEventListener(ProgressEvent.PROGRESS, thingsProgressHandler);
                _things.removeEventListener(ErrorEvent.ERROR, thingsErrorHandler);
                _things = null;
            }

            if (_sprites) {
                _sprites.unload();
                _sprites.removeEventListener(StorageEvent.LOAD, storageLoadHandler);
                _sprites.removeEventListener(StorageEvent.CHANGE, storageChangeHandler);
                _sprites.removeEventListener(ProgressEvent.PROGRESS, spritesProgressHandler);
                _sprites.removeEventListener(ErrorEvent.ERROR, spritesErrorHandler);
                _sprites = null;
            }

            _datFile = null;
            _sprFile = null;
            _version = null;
            _extended = false;
            _transparency = false;
            _errorMessage = null;
        }

        private function onNewThing(category:String):void
        {
            if (!ThingCategory.getCategory(category)) {
                throw new Error(Resources.getString("invalidCategory"));
            }

            //============================================================================
            // Add thing

            var thing:ThingType = ThingType.create(0, category);
            var result:ChangeResult = _things.addThing(thing, category);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            // Send thing to preview.
            onGetThing(thing.id, category);

            // Send message to log.
            var message:String = Resources.getString(
                "logAdded",
                toLocale(category),
                thing.id);

            Log.info(message);
        }

        private function onUpdateThing(thingData:ThingData, replaceSprites:Boolean):void
        {
            if (!thingData) {
                throw new NullArgumentError("thingData");
            }

            var result:ChangeResult;
            var thing:ThingType = thingData.thing;

            if (!_things.hasThingType(thing.category, thing.id)) {
                throw new Error(Resources.getString(
                    "thingNotFound",
                    toLocale(thing.category),
                    thing.id));
            }

            //============================================================================
            // Update sprites

            var sprites:Vector.<SpriteData> = thingData.sprites;
            var length:uint = sprites.length;
            var spritesIds:Vector.<uint> = new Vector.<uint>();
            var addedSpriteList:Array = [];
            var currentThing:ThingType = _things.getThingType(thing.id, thing.category);

            for (var i:uint = 0; i < length; i++) {
                var spriteData:SpriteData = sprites[i];
                var id:uint = thing.spriteIndex[i];

                if (id == uint.MAX_VALUE) {
                    if (spriteData.isEmpty()) {
                        thing.spriteIndex[i] = 0;
                    } else {

                        if (replaceSprites && i < currentThing.spriteIndex.length && currentThing.spriteIndex[i] != 0) {
                            result = _sprites.replaceSprite(currentThing.spriteIndex[i], spriteData.pixels);
                        } else {
                            result = _sprites.addSprite(spriteData.pixels);
                        }

                        if (!result.done) {
                            Log.error(result.message);
                            return;
                        }

                        spriteData = result.list[0];
                        thing.spriteIndex[i] = spriteData.id;
                        spritesIds[spritesIds.length] = spriteData.id;
                        addedSpriteList[addedSpriteList.length] = spriteData;
                    }
                } else {
                    if (!_sprites.hasSpriteId(id)) {
                        Log.error(Resources.getString("spriteNotFound", id));
                        return;
                    }
                }
            }

            //============================================================================
            // Update thing

            result = _things.replaceThing(thing, thing.category, thing.id);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            var message:String;

            // Sprites change message
            if (spritesIds.length > 0) {
                message = Resources.getString(
                    replaceSprites ? "logReplaced" : "logAdded",
                    toLocale("sprite", spritesIds.length > 1),
                    spritesIds);

                Log.info(message);

                this.setSelectedSpriteIds(spritesIds);
            }

            // Thing change message
            onGetThing(thingData.id, thingData.category);

            sendThingList(Vector.<uint>([ thingData.id ]), thingData.category);

            message = Resources.getString(
                "logChanged",
                toLocale(thing.category),
                thing.id);

            Log.info(message);
        }

        private function onExportThing(list:Vector.<PathHelper>,
                                       category:String,
                                       obdVersion:uint,
                                       clientVersion:Version,
                                       spriteSheetFlag:uint,
                                       transparentBackground:Boolean,
                                       jpegQuality:uint):void
        {
            if (!list)
                throw new NullArgumentError("list");

            if (!ThingCategory.getCategory(category))
                throw new ArgumentError(Resources.getString("invalidCategory"));

            if (!clientVersion)
                throw new NullArgumentError("version");

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Export things

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("exportingObjects")));

            var encoder:OBDEncoder = new OBDEncoder();
            var helper:SaveHelper = new SaveHelper();
            var backgoundColor:uint = (_transparency || transparentBackground) ? 0x00FF00FF : 0xFFFF00FF;
            var bytes:ByteArray;
            var bitmap:BitmapData;

            for (var i:uint = 0; i < length; i++) {
                var pathHelper:PathHelper = list[i];
                var thingData:ThingData = getThingData(pathHelper.id, category, obdVersion, clientVersion.value);
                var file:File = new File(pathHelper.nativePath);
                var name:String = FileUtil.getName(file);
                var format:String = file.extension;

                if (ImageFormat.hasImageFormat(format))
                {
                    bitmap = thingData.getSpriteSheet(null, backgoundColor);
                    bytes = ImageCodec.encode(bitmap, format, jpegQuality);
                    if (spriteSheetFlag != 0)
                        helper.addFile(ObUtils.getPatternsString(thingData.thing, spriteSheetFlag), name, "txt", file);

                }
                else if (format == OTFormat.OBD)
                {
                    bytes = encoder.encode(thingData);
                }
                helper.addFile(bytes, name, format, file);
            }
            helper.addEventListener(flash.events.ProgressEvent.PROGRESS, progressHandler);
            helper.addEventListener(Event.COMPLETE, completeHandler);
            helper.save();

            function progressHandler(event:flash.events.ProgressEvent):void
            {
                sendCommand(new ProgressCommand(ProgressBarID.DEFAULT, event.bytesLoaded, event.bytesTotal));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
            }
        }

        private function onReplaceThings(list:Vector.<ThingData>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Add sprites

            var result:ChangeResult;
            var spritesIds:Vector.<uint> = new Vector.<uint>();
            for (var i:uint = 0; i < length; i++) {
                var thing:ThingType = list[i].thing;
                var sprites:Vector.<SpriteData> = list[i].sprites;
                var len:uint = sprites.length;

                for (var k:uint = 0; k < len; k++) {
                    var spriteData:SpriteData = sprites[k];
                    var id:uint = spriteData.id;
                    if (spriteData.isEmpty()) {
                        id = 0;
                    } else if (!_sprites.hasSpriteId(id) || !_sprites.compare(id, spriteData.pixels)) {
                        result = _sprites.addSprite(spriteData.pixels);
                        if (!result.done) {
                            Log.error(result.message);
                            return;
                        }
                        id = _sprites.spritesCount;
                        spritesIds[spritesIds.length] = id;
                    }
                    thing.spriteIndex[k] = id;
                }
            }

            //============================================================================
            // Replace things

            var thingsToReplace:Vector.<ThingType> = new Vector.<ThingType>(length, true);
            var thingsIds:Vector.<uint> = new Vector.<uint>(length, true);
            for (i = 0; i < length; i++) {
                thingsToReplace[i] = list[i].thing;
                thingsIds[i] = list[i].id;
            }
            result = _things.replaceThings(thingsToReplace);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            var message:String;

            // Added sprites message
            if (spritesIds.length > 0)
            {
                this.sendSpriteList(Vector.<uint>([_sprites.spritesCount]));

                message = Resources.getString(
                    "logAdded",
                    toLocale("sprite", spritesIds.length > 1),
                    spritesIds);

                Log.info(message);
            }

            var category:String = list[0].thing.category;
            this.setSelectedThingIds(thingsIds, category);

            message = Resources.getString(
                "logReplaced",
                toLocale(category, thingsIds.length > 1),
                thingsIds);

            Log.info(message);
        }

        private function onReplaceThingsFromFiles(list:Vector.<PathHelper>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Load things

            var loader:ThingDataLoader = new ThingDataLoader();
            loader.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            loader.addEventListener(Event.COMPLETE, completeHandler);
            loader.addEventListener(ErrorEvent.ERROR, errorHandler);
            loader.loadFiles(list);

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("loading")));

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                onReplaceThings(loader.thingDataList);
            }

            function errorHandler(event:ErrorEvent):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                Log.error(event.text);
            }
        }

        private function onImportThings(list:Vector.<ThingData>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Add sprites

            var result:ChangeResult;
            var spritesIds:Vector.<uint> = new Vector.<uint>();
            for (var i:uint = 0; i < length; i++) {
                var thing:ThingType = list[i].thing;
                var sprites:Vector.<SpriteData> = list[i].sprites;
                var len:uint = sprites.length;

                for (var k:uint = 0; k < len; k++) {
                    var spriteData:SpriteData = sprites[k];
                    var id:uint = spriteData.id;
                    if (spriteData.isEmpty()) {
                        id = 0;
                    } else if (!_sprites.hasSpriteId(id) || !_sprites.compare(id, spriteData.pixels)) {
                        result = _sprites.addSprite(spriteData.pixels);
                        if (!result.done) {
                            Log.error(result.message);
                            return;
                        }
                        id = _sprites.spritesCount;
                        spritesIds[spritesIds.length] = id;
                    }
                    thing.spriteIndex[k] = id;
                }
            }

            //============================================================================
            // Add things

            var thingsToAdd:Vector.<ThingType> = new Vector.<ThingType>(length, true);
            for (i = 0; i < length; i++) {
                thingsToAdd[i] = list[i].thing;
            }
            result = _things.addThings(thingsToAdd);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            var addedThings:Array = result.list;

            //============================================================================
            // Send changes

            var message:String;

            if (spritesIds.length > 0)
            {
                this.sendSpriteList(Vector.<uint>([_sprites.spritesCount]));

                message = Resources.getString(
                    "logAdded",
                    toLocale("sprite", spritesIds.length > 1),
                    spritesIds);

                Log.info(message);
            }

            var thingsIds:Vector.<uint> = new Vector.<uint>(length, true);
            for (i = 0; i < length; i++) {
                thingsIds[i] = addedThings[i].id;
            }

            var category:String = list[0].thing.category;
            this.setSelectedThingIds(thingsIds, category);

            message = Resources.getString(
                "logAdded",
                toLocale(category, thingsIds.length > 1),
                thingsIds);

            Log.info(message);
        }

        private function onImportThingsFromFiles(list:Vector.<PathHelper>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Load things

            var loader:ThingDataLoader = new ThingDataLoader();
            loader.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            loader.addEventListener(Event.COMPLETE, completeHandler);
            loader.addEventListener(ErrorEvent.ERROR, errorHandler);
            loader.loadFiles(list);

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("loading")));

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                onImportThings(loader.thingDataList);
            }

            function errorHandler(event:ErrorEvent):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                Log.error(event.text);
            }
        }

        private function onDuplicateThing(list:Vector.<uint>, category:String):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            if (!ThingCategory.getCategory(category)) {
                throw new Error(Resources.getString("invalidCategory"));
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Duplicate things

            list.sort(Array.NUMERIC);

            var thingsCopyList:Vector.<ThingType> = new Vector.<ThingType>();

            for (var i:uint = 0; i < length; i++) {
                var thing:ThingType = _things.getThingType(list[i], category);
                if (!thing) {
                    throw new Error(Resources.getString(
                        "thingNotFound",
                        Resources.getString(category),
                        list[i]));
                }
                thingsCopyList[i] = thing.clone();
            }

            var result:ChangeResult = _things.addThings(thingsCopyList);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            var addedThings:Array = result.list;

            //============================================================================
            // Send changes

            length = addedThings.length;
            var thingIds:Vector.<uint> = new Vector.<uint>(length, true);
            for (i = 0; i < length; i++) {
                thingIds[i] = addedThings[i].id;
            }

            this.setSelectedThingIds(thingIds, category);

            thingIds.sort(Array.NUMERIC);
            var message:String = StringUtil.format(Resources.getString(
                "logDuplicated"),
                toLocale(category, thingIds.length > 1),
                list);

            Log.info(message);
        }

        private function onRemoveThings(list:Vector.<uint>, category:String, removeSprites:Boolean):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            if (!ThingCategory.getCategory(category)) {
                throw new ArgumentError(Resources.getString("invalidCategory"));
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Remove things

            var result:ChangeResult = _things.removeThings(list, category);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            var removedThingList:Array = result.list;

            //============================================================================
            // Remove sprites

            var removedSpriteList:Array;

            if (removeSprites) {
                var sprites:Object = {};
                var id:uint;

                length = removedThingList.length;
                for (var i:uint = 0; i < length; i++) {
                    var spriteIndex:Vector.<uint> = removedThingList[i].spriteIndex;
                    var len:uint = spriteIndex.length;
                    for (var k:uint = 0; k < len; k++) {
                        id = spriteIndex[k];
                        if (id != 0) {
                            sprites[id] = id;
                        }
                    }
                }

                var spriteIds:Vector.<uint> = new Vector.<uint>();
                for each(id in sprites) {
                    spriteIds[spriteIds.length] = id;
                }

                result = _sprites.removeSprites(spriteIds);
                if (!result.done) {
                    Log.error(result.message);
                    return;
                }

                removedSpriteList = result.list;
            }

            //============================================================================
            // Send changes

            var message:String;

            length = removedThingList.length;
            var thingIds:Vector.<uint> = new Vector.<uint>(length, true);
            for (i = 0; i < length; i++) {
                thingIds[i] = removedThingList[i].id;
            }

            this.setSelectedThingIds(thingIds, category);

            thingIds.sort(Array.NUMERIC);
            message = Resources.getString(
                "logRemoved",
                toLocale(category, thingIds.length > 1),
                thingIds);

            Log.info(message);

            // Sprites changes
            if (removeSprites && spriteIds.length != 0)
            {
                spriteIds.sort(Array.NUMERIC);
                sendSpriteList(Vector.<uint>([ spriteIds[0] ]));

                message = Resources.getString(
                    "logRemoved",
                    toLocale("sprite", spriteIds.length > 1),
                    spriteIds);

                Log.info(message);
            }
        }

        private function onGetThingList(targetId:uint, category:String):void
        {
            if (isNullOrEmpty(category))
                throw new NullOrEmptyArgumentError("category");

            sendThingList(Vector.<uint>([ targetId ]), category);
        }

        private function onFindThing(category:String, properties:Vector.<ThingProperty>):void
        {
            if (!ThingCategory.getCategory(category)) {
                throw new ArgumentError(Resources.getString("invalidCategory"));
            }

            if (!properties) {
                throw new NullArgumentError("properties");
            }

            var list:Array = [];
            var things:Array = _things.findThingTypeByProperties(category, properties);
            var length:uint = things.length;

            for (var i:uint = 0; i < length; i++) {
                var listItem : ThingListItem = new ThingListItem();
                listItem.thing = things[i];
                listItem.pixels = getBitmapPixels(listItem.thing);
                list[i] = listItem;
            }
            sendCommand(new FindResultCommand(FindResultCommand.THINGS, list));
        }

        private function onReplaceSprites(sprites:Vector.<SpriteData>):void
        {
            if (!sprites) {
                throw new NullArgumentError("sprites");
            }

            var length:uint = sprites.length;
            if (length == 0) return;

            //============================================================================
            // Replace sprites

            var result:ChangeResult = _sprites.replaceSprites(sprites);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            var spriteIds:Vector.<uint> = new Vector.<uint>(length, true);
            for (var i:uint = 0; i < length; i++) {
                spriteIds[i] = sprites[i].id;
            }

            this.setSelectedSpriteIds(spriteIds);

            var message:String = Resources.getString(
                "logReplaced",
                toLocale("sprite", sprites.length > 1),
                spriteIds);

            Log.info(message);
        }

        private function onReplaceSpritesFromFiles(list:Vector.<PathHelper>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            if (list.length == 0) return;

            //============================================================================
            // Load sprites

            var loader:SpriteDataLoader = new SpriteDataLoader();
            loader.addEventListener(Event.COMPLETE, completeHandler);
            loader.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            loader.loadFiles(list);

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("loading")));

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                onReplaceSprites(loader.spriteDataList);
            }
        }

        private function onAddSprites(sprites:Vector.<ByteArray>):void
        {
            if (!sprites) {
                throw new NullArgumentError("sprites");
            }

            if (sprites.length == 0) return;

            //============================================================================
            // Add sprites

            var result:ChangeResult = _sprites.addSprites(sprites);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            var spriteAddedList:Array = result.list;

            //============================================================================
            // Send changes to application

            var ids:Array = [];
            var length:uint = spriteAddedList.length;
            for (var i:uint = 0; i < length; i++) {
                ids[i] = spriteAddedList[i].id;
            }

            sendSpriteList(Vector.<uint>([ ids[0] ]));

            ids.sort(Array.NUMERIC);
            var message:String = Resources.getString(
                "logAdded",
                toLocale("sprite", ids.length > 1),
                ids);

            Log.info(message);
        }

        private function onImportSpritesFromFiles(list:Vector.<PathHelper>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            if (list.length == 0) return;

            //============================================================================
            // Load sprites

            var loader:SpriteDataLoader = new SpriteDataLoader();
            loader.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            loader.addEventListener(Event.COMPLETE, completeHandler);
            loader.addEventListener(ErrorEvent.ERROR, errorHandler);
            loader.loadFiles(list);

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("loading")));

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));

                var spriteDataList:Vector.<SpriteData> = loader.spriteDataList;
                var length:uint = spriteDataList.length;
                var sprites:Vector.<ByteArray> = new Vector.<ByteArray>(length, true);

                VectorUtils.sortOn(spriteDataList, "id", Array.NUMERIC | Array.DESCENDING);

                for (var i:uint = 0; i < length; i++) {
                    sprites[i] = spriteDataList[i].pixels;
                }

                onAddSprites(sprites);
            }

            function errorHandler(event:ErrorEvent):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
                Log.error(event.text);
            }
        }

        private function onExportSprites(list:Vector.<PathHelper>,
                                         transparentBackground:Boolean,
                                         jpegQuality:uint):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            var length:uint = list.length;
            if (length == 0) return;

            //============================================================================
            // Save sprites

            sendCommand(new ShowProgressBarCommand(ProgressBarID.DEFAULT, Resources.getString("exportingSprites")));

            var helper:SaveHelper = new SaveHelper();

            for (var i:uint = 0; i < length; i++) {
                var pathHelper:PathHelper = list[i];
                var file:File = new File(pathHelper.nativePath);
                var name:String = FileUtil.getName(file);
                var format:String = file.extension;

                if (ImageFormat.hasImageFormat(format) && pathHelper.id != 0) {
                    var bitmap:BitmapData = _sprites.getBitmap(pathHelper.id, transparentBackground);
                    if (bitmap) {
                        var bytes:ByteArray = ImageCodec.encode(bitmap, format, jpegQuality);
                        helper.addFile(bytes, name, format, file);
                    }
                }
            }
            helper.addEventListener(flash.events.ProgressEvent.PROGRESS, progressHandler);
            helper.addEventListener(Event.COMPLETE, completeHandler);
            helper.save();

            function progressHandler(event:flash.events.ProgressEvent):void
            {
                sendCommand(new ProgressCommand(ProgressBarID.DEFAULT, event.bytesLoaded, event.bytesTotal));
            }

            function completeHandler(event:Event):void
            {
                sendCommand(new HideProgressBarCommand(ProgressBarID.DEFAULT));
            }
        }

        private function onNewSprite():void
        {
            if (_sprites.isFull) {
                Log.error(Resources.getString("spritesLimitReached"));
                return;
            }

            //============================================================================
            // Add sprite

            var rect:Rectangle = new Rectangle(0, 0, otlib.sprites.Sprite.DEFAULT_SIZE, otlib.sprites.Sprite.DEFAULT_SIZE);
            var pixels:ByteArray = new BitmapData(rect.width, rect.height, true, 0).getPixels(rect);
            var result:ChangeResult = _sprites.addSprite(pixels);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            sendSpriteList(Vector.<uint>([ _sprites.spritesCount ]));

            var message:String = Resources.getString(
                "logAdded",
                Resources.getString("sprite"),
                _sprites.spritesCount);
            Log.info(message);
        }

        private function onRemoveSprites(list:Vector.<uint>):void
        {
            if (!list) {
                throw new NullArgumentError("list");
            }

            //============================================================================
            // Removes sprites

            var result:ChangeResult = _sprites.removeSprites(list);
            if (!result.done) {
                Log.error(result.message);
                return;
            }

            //============================================================================
            // Send changes

            // Select sprites
            this.setSelectedSpriteIds(list);

            // Send message to log
            var message:String = Resources.getString(
                "logRemoved",
                toLocale("sprite", list.length > 1),
                list);

            Log.info(message);
        }

        private function onGetSpriteList(targetId:uint):void
        {
            sendSpriteList(Vector.<uint>([ targetId ]));
        }

        private function onNeedToReload(extended:Boolean,
                                        transparency:Boolean,
                                        improvedAnimations:Boolean):void
        {
            onLoadFiles(_datFile.nativePath,
                        _sprFile.nativePath,
                        _version,
                        extended,
                        transparency,
                        improvedAnimations);
        }

        private function onFindSprites(unusedSprites:Boolean, emptySprites:Boolean):void
        {
            var finder:SpritesFinder = new SpritesFinder(_things, _sprites);
            finder.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            finder.addEventListener(Event.COMPLETE, completeHandler);
            finder.start(unusedSprites, emptySprites);

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(ProgressBarID.FIND,
                                                event.loaded,
                                                event.total));
            }

            function completeHandler(event:Event):void
            {
                var command:Command = new FindResultCommand(FindResultCommand.SPRITES,
                                                            finder.foundList);
                sendCommand(command);
            }
        }

        private function onOptimizeSprites(unusedSprites:Boolean, emptySprites:Boolean):void
        {
            var optimizer:SpritesOptimizer = new SpritesOptimizer(_things, _sprites);
            optimizer.addEventListener(ProgressEvent.PROGRESS, progressHandler);
            optimizer.addEventListener(Event.COMPLETE, completeHandler);
            optimizer.start(unusedSprites, emptySprites);

            function progressHandler(event:ProgressEvent):void
            {
                sendCommand(new ProgressCommand(ProgressBarID.OPTIMIZE,
                                                event.loaded,
                                                event.total,
                                                event.label));
            }

            function completeHandler(event:Event):void
            {
                if (optimizer.removedCount > 0)
                {
                    sendClientInfo();
                    sendSpriteList(Vector.<uint>([0]));
                    sendThingList(Vector.<uint>([100]), ThingCategory.ITEM);
                }

                var command:Command = new OptimizeSpritesResultCommand(optimizer.removedCount,
                                                                       optimizer.oldCount,
                                                                       optimizer.newCount);

                sendCommand(command);
            }
        }

        private function clientLoadComplete():void
        {
            sendCommand(new HideProgressBarCommand(ProgressBarID.DAT_SPR));
            sendClientInfo();
            sendThingList(Vector.<uint>([ThingTypeStorage.MIN_ITEM_ID]), ThingCategory.ITEM);
            sendThingData(Vector.<uint>([ThingTypeStorage.MIN_ITEM_ID]), ThingCategory.ITEM);
            sendSpriteList(Vector.<uint>([0]));
            Log.info(Resources.getString("loadComplete"));
        }

        private function clientCompileComplete():void
        {
            sendCommand(new HideProgressBarCommand(ProgressBarID.DAT_SPR));
            sendClientInfo();
            Log.info(Resources.getString("compileComplete"));
        }

        public function sendClientInfo():void
        {
            var info:ClientInfo = new ClientInfo();
            info.loaded = clientLoaded;

            if (info.loaded)
            {
                info.clientVersion = _version.value;
                info.clientVersionStr = _version.valueStr;
                info.datSignature = _things.signature;
                info.minItemId = ThingTypeStorage.MIN_ITEM_ID;
                info.maxItemId = _things.itemsCount;
                info.minOutfitId = ThingTypeStorage.MIN_OUTFIT_ID;
                info.maxOutfitId = _things.outfitsCount;
                info.minEffectId = ThingTypeStorage.MIN_EFFECT_ID;
                info.maxEffectId = _things.effectsCount;
                info.minMissileId = ThingTypeStorage.MIN_MISSILE_ID;
                info.maxMissileId = _things.missilesCount;
                info.sprSignature = _sprites.signature;
                info.minSpriteId = 0;
                info.maxSpriteId = _sprites.spritesCount;
                info.extended = _extended;
                info.transparency = _transparency;
                info.improvedAnimations = _improvedAnimations;
                info.changed = clientChanged;
                info.isTemporary = clientIsTemporary;
            }

            sendCommand(new SetClientInfoCommand(info));
        }

        private function sendThingList(selectedIds:Vector.<uint>, category:String):void
        {
            if (!_things || !_things.loaded) {
                throw new Error(Resources.getString("metadataNotLoaded"));
            }

            var first:uint = _things.getMinId(category);
            var last:uint = _things.getMaxId(category);
            var length:uint = selectedIds.length;

            if (length > 1) {
                selectedIds.sort(Array.NUMERIC | Array.DESCENDING);
                if (selectedIds[length - 1] > last) {
                    selectedIds = Vector.<uint>([last]);
                }
            }

            var target:uint = length == 0 ? 0 : selectedIds[0];
            var min:uint = Math.max(first, ObUtils.hundredFloor(target));
            var diff:uint = (category != ThingCategory.ITEM && min == first) ? 1 : 0;
            var max:uint = Math.min((min - diff) + (_thingListAmount - 1), last);
            var list:Vector.<ThingListItem> = new Vector.<ThingListItem>();

            for (var i:uint = min; i <= max; i++) {
                var thing:ThingType = _things.getThingType(i, category);
                if (!thing) {
                    throw new Error(Resources.getString(
                        "thingNotFound",
                        Resources.getString(category),
                        i));
                }

                var listItem:ThingListItem = new ThingListItem();
                listItem.thing = thing;
                listItem.pixels = getBitmapPixels(thing);
                list.push(listItem);
            }

            sendCommand(new SetThingListCommand(selectedIds, list));
        }

        private function sendThingData(id:uint, category:String):void
        {
            var thingData:ThingData = getThingData(id, category, OBDVersions.OBD_VERSION_2, _version.value);
            if (thingData)
                sendCommand(new SetThingDataCommand(thingData));
        }

        private function sendSpriteList(selectedIds:Vector.<uint>):void
        {
            if (!selectedIds) {
                throw new NullArgumentError("selectedIds");
            }

            if (!_sprites || !_sprites.loaded) {
                throw new Error(Resources.getString("spritesNotLoaded"));
            }

            var length:uint = selectedIds.length;
            if (length > 1) {
                selectedIds.sort(Array.NUMERIC | Array.DESCENDING);
                if (selectedIds[length - 1] > _sprites.spritesCount) {
                    selectedIds = Vector.<uint>([_sprites.spritesCount]);
                }
            }

            var target:uint = length == 0 ? 0 : selectedIds[0];
            var first:uint = 0;
            var last:uint = _sprites.spritesCount;
            var min:uint = Math.max(first, ObUtils.hundredFloor(target));
            var max:uint = Math.min(min + (_spriteListAmount - 1), last);
            var list:Vector.<SpriteData> = new Vector.<SpriteData>();

            for (var i:uint = min; i <= max; i++) {
                var pixels:ByteArray = _sprites.getPixels(i);
                if (!pixels) {
                    throw new Error(Resources.getString("spriteNotFound", i));
                }

                var spriteData:SpriteData = new SpriteData();
                spriteData.id = i;
                spriteData.pixels = pixels;
                list.push(spriteData);
            }

            sendCommand(new SetSpriteListCommand(selectedIds, list));
        }

        private function getBitmapPixels(thing:ThingType):ByteArray
        {
            var size:uint = otlib.sprites.Sprite.DEFAULT_SIZE;
            var width:uint = thing.width;
            var height:uint = thing.height;
            var layers:uint = thing.layers;
            var bitmap:BitmapData = new BitmapData(width * size, height * size, true, 0xFF636363);
            var x:uint;

            if (thing.category == ThingCategory.OUTFIT) {
                layers = 1;
                x = thing.frames > 1 ? 2 : 0;
            }

            for (var l:uint = 0; l < layers; l++) {
                for (var w:uint = 0; w < width; w++) {
                    for (var h:uint = 0; h < height; h++) {
                        var index:uint = thing.getSpriteIndex(w, h, l, x, 0, 0, 0);
                        var px:int = (width - w - 1) * size;
                        var py:int = (height - h - 1) * size;
                        _sprites.copyPixels(thing.spriteIndex[index], bitmap, px, py);
                    }
                }
            }
            return bitmap.getPixels(bitmap.rect);
        }

        private function getThingData(id:uint, category:String, obdVersion:uint, clientVersion:uint):ThingData
        {
            if (!ThingCategory.getCategory(category)) {
                throw new Error(Resources.getString("invalidCategory"));
            }

            var thing:ThingType = _things.getThingType(id,  category);
            if (!thing) {
                throw new Error(Resources.getString(
                    "thingNotFound",
                    Resources.getString(category),
                    id));
            }

            var sprites:Vector.<SpriteData> = new Vector.<SpriteData>();
            var spriteIndex:Vector.<uint> = thing.spriteIndex;
            var length:uint = spriteIndex.length;

            for (var i:uint = 0; i < length; i++) {
                var spriteId:uint = spriteIndex[i];
                var pixels:ByteArray = _sprites.getPixels(spriteId);
                if (!pixels) {
                    Log.error(Resources.getString("spriteNotFound", spriteId));
                    pixels = _sprites.alertSprite.getPixels();
                }

                var spriteData:SpriteData = new SpriteData();
                spriteData.id = spriteId;
                spriteData.pixels = pixels;
                sprites.push(spriteData);
            }
            return ThingData.create(obdVersion, clientVersion, thing, sprites);
        }

        private function toLocale(bundle:String, plural:Boolean = false):String
        {
            return Resources.getString(bundle + (plural ? "s" : "")).toLowerCase();
        }

        //--------------------------------------
        // Event Handlers
        //--------------------------------------

        protected function storageLoadHandler(event:StorageEvent):void
        {
            if (event.target == _things || event.target == _sprites)
            {
                if (_things.loaded && _sprites.loaded)
                    this.clientLoadComplete();
            }
        }

        protected function storageChangeHandler(event:StorageEvent):void
        {
            sendClientInfo();
        }

        protected function thingsProgressHandler(event:ProgressEvent):void
        {
            sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
        }

        protected function thingsErrorHandler(event:ErrorEvent):void
        {
            // Try load as extended.
            if (!_things.loaded && !_extended)
            {
                _errorMessage = event.text;
                onLoadFiles(_datFile.nativePath,
                            _sprFile.nativePath,
                            _version,
                            true,
                            _transparency,
                            _improvedAnimations);
            }
            else
            {
                if (_errorMessage)
                {
                    Log.error(_errorMessage);
                    _errorMessage = null;
                }
                else
                    Log.error(event.text);
            }
        }

        protected function spritesProgressHandler(event:ProgressEvent):void
        {
            sendCommand(new ProgressCommand(event.id, event.loaded, event.total));
        }

        protected function spritesErrorHandler(event:ErrorEvent):void
        {
            Log.error(event.text, "", event.errorID);
        }
    }
}
