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

package otlib.core
{
    import flash.events.IEventDispatcher;
    import flash.filesystem.File;

    import otlib.utils.ClientInfo;

    public interface IVersionStorage extends IEventDispatcher
    {
        function get file():File;
        function get changed():Boolean;
        function get loaded():Boolean;

        function load(file:File):Boolean;
        function addVersion(value:uint, dat:uint, spr:uint, otb:uint):Version;
        function removeVersion(version:Version):Version;
        function save(file:File):void;
        function getList():Array;
        function getFromClientInfo(info:ClientInfo):Version;
        function getByValue(value:uint):Vector.<Version>;
        function getByValueString(value:String):Version;
        function getBySignatures(datSignature:uint, sprSignature:uint):Version;
        function getByOtbVersion(otb:uint):Vector.<Version>;
        function unload():void;
    }
}
