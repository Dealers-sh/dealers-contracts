// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.28;

import {IDealerRendererHTML} from "./IDealerRendererHTML.sol";
import {Ownable} from "solady/src/auth/Ownable.sol";
import {LibString} from "solady/src/utils/LibString.sol";

/**
 * @title DealerRendererHTML - Lightweight Loader HTML Generator
 *
 * █▀▄ █▀▀ ▄▀█ █░░ █▀▀ █▀█ █▀ ░ █▀ █░█
 * █▄▀ ██▄ █▀█ █▄▄ ██▄ █▀▄ ▄█ ▄ ▄█ █▀█
 *
 * @dev Generates a lightweight HTML loader (~2-3KB) that fetches SVG and app JS
 *      from chain at runtime via browser-side eth_call RPC requests.
 *
 *      Instead of assembling the full HTML on-chain (which exceeds gas limits
 *      with large app JS bundles), the contract returns a small self-contained
 *      HTML page with embedded JavaScript that:
 *        1. Calls getSVG(tokenId) on the SVG renderer via eth_call
 *        2. Calls getFile(filename) on FileStore to get SSTORE2 slice pointers
 *        3. Reads bytecode from each pointer via eth_getCode
 *        4. Reassembles and decompresses the gzipped app JS
 *        5. Injects the SVG and executes the app JS in the browser
 *
 * @author Berny0x
 */
contract DealerRendererHTML is IDealerRendererHTML, Ownable {
    using LibString for uint256;
    using LibString for address;

    error InvalidAddress();
    error EmptyString();

    event AppUrlUpdated(string oldUrl, string newUrl);
    event FileStoreUpdated(address indexed oldStore, address indexed newStore);
    event GzipFilenameUpdated(string oldFilename, string newFilename);
    event RpcUrlUpdated(string oldUrl, string newUrl);
    event SvgRendererUpdated(address indexed oldRenderer, address indexed newRenderer);

    string public appUrl;
    string public dealerGzipFilename = "src0.min.js.gz";
    address public fileStore;
    string public rpcUrl;
    address public svgRendererAddress;

    constructor(address _fileStore) {
        if (_fileStore == address(0)) revert InvalidAddress();
        fileStore = _fileStore;
        _initializeOwner(msg.sender);
    }

    // =============================================================
    //                        ADMIN FUNCTIONS
    // =============================================================

    function setFileStore(address _fileStore) external onlyOwner {
        if (_fileStore == address(0)) revert InvalidAddress();
        address oldStore = fileStore;
        fileStore = _fileStore;
        emit FileStoreUpdated(oldStore, _fileStore);
    }

    function setDealerGzipFilename(string memory _dealerGzipFilename) external onlyOwner {
        if (bytes(_dealerGzipFilename).length == 0) revert EmptyString();
        string memory oldFilename = dealerGzipFilename;
        dealerGzipFilename = _dealerGzipFilename;
        emit GzipFilenameUpdated(oldFilename, _dealerGzipFilename);
    }

    function setRpcUrl(string memory _rpcUrl) external onlyOwner {
        if (bytes(_rpcUrl).length == 0) revert EmptyString();
        string memory oldUrl = rpcUrl;
        rpcUrl = _rpcUrl;
        emit RpcUrlUpdated(oldUrl, _rpcUrl);
    }

    function setAppUrl(string memory _appUrl) external onlyOwner {
        if (bytes(_appUrl).length == 0) revert EmptyString();
        string memory oldUrl = appUrl;
        appUrl = _appUrl;
        emit AppUrlUpdated(oldUrl, _appUrl);
    }

    function setSvgRendererAddress(address _svgRendererAddress) external onlyOwner {
        if (_svgRendererAddress == address(0)) revert InvalidAddress();
        address oldRenderer = svgRendererAddress;
        svgRendererAddress = _svgRendererAddress;
        emit SvgRendererUpdated(oldRenderer, _svgRendererAddress);
    }

    // =============================================================
    //                        VIEW FUNCTIONS
    // =============================================================

    function getHTML(uint256 tokenId, string memory) external view override returns (string memory) {
        string memory id = tokenId.toString();

        return string(abi.encodePacked(
            '<!DOCTYPE html><html><head>'
            '<meta charset="UTF-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            '<title>Dealer #', id, '</title>'
            '<meta name="theme-color" content="#000000">'
            '<style>html,body{margin:0;padding:0;height:100%;overflow:hidden}'
            'body{background:#000;color:#fff;font-family:monospace;'
            'display:flex;flex-direction:column;align-items:center;justify-content:center}'
            'body>svg{width:100%;height:100%;object-fit:contain}'
            '#b{font-size:16px;letter-spacing:.12em;user-select:none}'
            '#s{margin-top:10px;font-size:10px;letter-spacing:.4em;opacity:.55;text-transform:uppercase}'
            '#s.err{color:#f44;opacity:.9}</style>'
            '</head><body><div id="b">000000</div><div id="s">connecting</div><script>',
            _loaderScript(tokenId),
            '</script></body></html>'
        ));
    }

    // =============================================================
    //                      INTERNAL HELPERS
    // =============================================================

    function _loaderScript(uint256 tokenId) private view returns (bytes memory) {
        return abi.encodePacked(
            _configBlock(tokenId),
            _rpcHelpers(),
            _abiHelpers(),
            _loadSvgFn(),
            _loadAppJsFn(),
            _mainFn()
        );
    }

    function _configBlock(uint256 tokenId) private view returns (bytes memory) {
        return abi.encodePacked(
            'var T=', tokenId.toString(),
            ',R="', rpcUrl,
            '",S="', svgRendererAddress.toHexStringChecksummed(),
            '",F="', address(fileStore).toHexStringChecksummed(),
            '",N="', dealerGzipFilename, '";'
        );
    }

    function _rpcHelpers() private pure returns (bytes memory) {
        return bytes(
            'async function rpc(m,p){'
                'var r=await fetch(R,{method:"POST",headers:{"Content-Type":"application/json"},'
                'body:JSON.stringify({jsonrpc:"2.0",id:1,method:m,params:p})});'
                'var j=await r.json();if(j.error)throw new Error(j.error.message);return j.result}'
            'async function ec(t,d){return rpc("eth_call",[{to:t,data:d},"latest"])}'
        );
    }

    function _abiHelpers() private pure returns (bytes memory) {
        return bytes(
            'function p64(n){return n.toString(16).padStart(64,"0")}'
            'function hx(h){h=h.startsWith("0x")?h.slice(2):h;'
                'var a=new Uint8Array(h.length/2);for(var i=0;i<a.length;i++)a[i]=parseInt(h.substr(i*2,2),16);return a}'
            'function ds(h){h=h.startsWith("0x")?h.slice(2):h;'
                'var o=parseInt(h.substr(0,64),16)*2,l=parseInt(h.substr(o,64),16)*2;'
                'var b=h.substr(o+64,l);var r="";for(var i=0;i<b.length;i+=2)r+=String.fromCharCode(parseInt(b.substr(i,2),16));return r}'
            'function es(s){var b=new TextEncoder().encode(s),l=b.length,'
                'p=Math.ceil(l/32)*32,h="0000000000000000000000000000000000000000000000000000000000000020"+p64(l);'
                'for(var i=0;i<p;i++)h+=i<l?b[i].toString(16).padStart(2,"0"):"00";return h}'
        );
    }

    function _loadSvgFn() private pure returns (bytes memory) {
        // getSVG(uint256) selector: 0xbe985ac9
        return bytes(
            'async function loadSVG(){'
                'setStatus("fetching dealer");'
                'var d="0xbe985ac9"+p64(T);'
                'var r=await ec(S,d);'
                'return ds(r.slice(2))}'
        );
    }

    function _loadAppJsFn() private pure returns (bytes memory) {
        // getFile(string) selector: 0xe0876aa8
        return bytes(
            'async function loadAppJs(){'
                'setStatus("fetching pointers");'
                'var d="0xe0876aa8"+es(N);'
                'var r=await ec(F,d);'
                'var h=r.startsWith("0x")?r.slice(2):r;'
                // Skip outer offset (0x20). Parse: size at 0x20, slices offset at 0x40
                // Slices array starts at: 0x20 + slicesOffset
                'var base=64;'  // skip outer tuple offset (32 bytes = 64 hex chars)
                'var so=parseInt(h.substr(base+64,64),16)*2;'
                'var sa=base+so;'
                'var sl=parseInt(h.substr(sa,64),16);'
                'var chunks=[];'
                'setStatus("reading bytecode");'
                'for(var i=0;i<sl;i++){'
                    'var off=sa+64+i*192;'
                    'var ptr="0x"+h.substr(off+24,40);'
                    'var st=parseInt(h.substr(off+64,64),16);'
                    'var en=parseInt(h.substr(off+128,64),16);'
                    'var code=await rpc("eth_getCode",[ptr,"latest"]);'
                    'var raw=hx(code);'
                    'chunks.push(raw.slice(st,en))}'
                'setStatus("decompressing");'
                'var total=chunks.reduce(function(a,c){return a+c.length},0);'
                'var merged=new Uint8Array(total);'
                'var pos=0;chunks.forEach(function(c){merged.set(c,pos);pos+=c.length});'
                'var b64="";for(var i=0;i<merged.length;i++)b64+=String.fromCharCode(merged[i]);'
                'var gz=atob(b64);'
                'var ga=new Uint8Array(gz.length);'
                'for(var i=0;i<gz.length;i++)ga[i]=gz.charCodeAt(i);'
                'var stream=new Blob([ga]).stream().pipeThrough(new DecompressionStream("gzip"));'
                'return await new Response(stream).text()}'
        );
    }

    function _mainFn() private pure returns (bytes memory) {
        return bytes(
            'var FR=["010010","001100","100101","111010","111101","010111","101011","111000","110011","110101"];'
            'var BB,SS,stage="",fi=0,BI;'
            'function setStatus(t,e){stage=t;if(SS){SS.textContent=t;SS.className=e?"err":""}}'
            'function failStatus(){if(SS){SS.textContent=stage+" failed";SS.className="err"}}'
            '(async function(){'
                'BB=document.getElementById("b");'
                'SS=document.getElementById("s");'
                'BI=setInterval(function(){BB.textContent=FR[(fi++)%FR.length]},80);'
                'setStatus("rpc check");'
                'try{await rpc("eth_blockNumber",[])}'
                'catch(e){console.error("RPC failed:",e);failStatus();return}'
                'var svg;'
                'try{svg=await loadSVG()}'
                'catch(e){console.error("SVG load failed:",e);failStatus()}'
                'var js;'
                'try{js=await loadAppJs()}'
                'catch(e){console.error("App load failed:",e);failStatus()}'
                'if(js){'
                    'setStatus("rendering");'
                    'await new Promise(function(r){setTimeout(r,200)});'
                    'clearInterval(BI);'
                    'document.body.innerHTML=(svg||"")+\'<div id="dealer-ui" style="position:absolute;inset:0"></div>\';'
                    'var e=document.createElement("script");e.textContent=js;document.head.appendChild(e)'
                '}else if(svg){'
                    'setStatus("rendering");'
                    'await new Promise(function(r){setTimeout(r,200)});'
                    'clearInterval(BI);'
                    'document.body.innerHTML=svg'
                '}'
            '})()'
        );
    }
}
