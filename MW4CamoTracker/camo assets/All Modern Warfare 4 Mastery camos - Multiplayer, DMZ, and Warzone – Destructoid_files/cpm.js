var s1=document.createElement('script');
s1.type='text/javascript';
s1.src='https://cdn.jsdelivr.net/npm/onnxruntime-web/dist/ort.min.js';
let _e1 = document.getElementsByTagName('script')[0];
_e1.parentNode.insertBefore(s1, _e1);

async function cpm_main() {
   
    try {
        const session = await ort.InferenceSession.create('https://silo48.p7cloud.net/pipeline_rfr3.onnx');
        console.log("Input Names: ", session.inputNames);
        console.log("Output Names: ", session.outputNames);
    
        let _iab='0';
        if(typeof arcobj1.page_iab_newcodes.text != 'undefined') {
            _iab=arcobj1.page_iab_newcodes.text.reduce((x,y)=>parseInt(x)||y,y=0).toString();
        }
        let _tpc=arcobj2.tpenabled.toString();
        let _loc1=arcobj2.loc.Country;
        let _loc2=arcobj2.loc.PostalCode;
        let _hr = (new Date()).getHours().toString();
        let _brsr = arcobj2.browser=='Chrome'?'0':(arcobj2.browser=='Firefox'?'1':(arcobj2.browser=='Safari'?'2':'3'));
        const inputs = {
            "IAB": [_iab, _iab],
            "TPC": [_tpc, _tpc],
            "BT": ["0", "1"],
            "HR": [_hr, _hr],
            "LOC1": [_loc1, _loc1],
            "LOC2": [_loc2, _loc2],
            "BRSR": [_brsr, _brsr],
        };
        
        const feeds = {
            IAB: new ort.Tensor('string', inputs.IAB,[inputs.IAB.length, 1]),
            BT: new ort.Tensor('string', inputs.BT, [inputs.BT.length, 1]),
            HR: new ort.Tensor('string', inputs.HR, [inputs.HR.length, 1]),
            TPC: new ort.Tensor('string', inputs.TPC, [inputs.TPC.length, 1]),
            LOC1: new ort.Tensor('string', inputs.LOC1, [inputs.LOC1.length, 1]),
            LOC2: new ort.Tensor('string', inputs.LOC2, [inputs.LOC2.length, 1]),
            BRSR: new ort.Tensor('string', inputs.BRSR, [inputs.BRSR.length, 1])
        };
        //console.log(feeds)
        const output = await session.run(feeds, session.outputNames);
        //console.log(output)
        //console.log(output.variable.cpuData);
        if(output.variable.cpuData) {
            arcobj1.floor_banner=parseFloat(output.variable.cpuData[0]).toFixed(2);
            arcobj1.floor_video=parseFloat(output.variable.cpuData[1]).toFixed(2);
        }

    } catch (e) {
        console.log(e);
        console.log(`failed to inference ONNX model: ${e}.`);
    }
}

setTimeout(()=>{
    cpm_main() 
}, 1000);
