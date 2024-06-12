"use client" 
import React, { useState, ChangeEvent } from 'react'; 
 
interface Inputs { 
  active:string, 
  liquidation:string, 
  margin: string; 
  leverage: string; 
  token: string; 
  profit: string; 
  shares: string; 
  funding: string; 
  entry:string 
} 
 
const Page: React.FC = () => { 
  const [inputs, setInputs] = useState<Inputs>({ 
    active:'', 
    margin: '', 
    leverage: '', 
    liquidation:'', 
    entry:'', 
    token: '', 
    profit: '', 
    shares: '', 
    funding: '' 
  }); 
 
  const handleChange = (e: ChangeEvent<HTMLInputElement>) => { 
    const { name, value } = e.target; 
    setInputs({ ...inputs, [name]: value }); 
  }; 
 
  return ( 
    <div className='mt-[100px] flex justify-center flex-col items-center mb-[100px]'> 
      <h1 className='text-3xl font-bold text-blue-600'>Advanced Charts Documentation</h1> 
      <p className='mt-[35px] text-xl font-medium'> 
        Your serves, your data, TradingView's charts - our documentation will 
        <br /> guide you through all the stages of integration & much more 
      </p> 
      <button className='mt-[50px] border border-2 px-[15px] py-[10px] text-xl text-white bg-blue-600 border-transparent font-bold'> 
        Get Started 
      </button> 
      <button className='mt-[30px] border border-2 px-[15px] py-[10px] font-bold text-xl bg-black text-white border-transparent'> 
        Explore 
      </button> 
 
      <div className='border border-transparent shadow-2xl mt-[50px] bg-slate-900' style={{ boxShadow: '0 10px 20px rgba(29, 78, 216, 0.5)' }}> 
        <img className='w-2/3 mx-auto px-[10px] mt-[0px]'  
          src='https://www.tradingview.com/charting-library-docs/img/landing-chart/landing-chart-v27-dark-2314w.avif'  
          alt='img' 
        /> 
      </div> 
 
      <div className='mt-[100px] px-[10px] mx-auto'> 
        <h1 className='text-xl font-medium text-center mb-[20px]'>Table</h1> 
        <table> 
          <tbody> 
            <tr> 
            <td> 
                <label>Active</label> 
                <input 
                  type="text" 
                  name="active" 
                  value={inputs.margin} 
                  onChange={handleChange} 
                  placeholder="Enter Margin" 
                /> 
              </td> 
              <td> 
                <label>Margin</label> 
                <input 
                  type="text" 
                  name="margin" 
                  value={inputs.margin} 
                  onChange={handleChange} 
                  placeholder="Enter Margin" 
                /> 
              </td> 
              <td> 
                <label>Leverage</label> 
                <input 
                  type="text" 
                  name="leverage" 
                  value={inputs.leverage} 
                  onChange={handleChange} 
                  placeholder="Enter Leverage" 
                /> 
              </td> 
              <td> 
                <label>Token</label> 
                <input 
                  type="text" 
                  name="token" 
                  value={inputs.token} 
                  onChange={handleChange} 
                  placeholder="Enter Token" 
                /> 
              </td> 
              <td> 
                <label>Entry</label> 
                <input 
                  type="text" 
                  name="entry" 
                  value={inputs.token} 
                  onChange={handleChange} 
                  placeholder="Enter Token" 
                /> 
              </td> 
              <td> 
                <label>Liquidation</label> 
                <input 
                  type="text" 
                  name="liquidation" 
                  value={inputs.profit} 
                  onChange={handleChange} 
                  placeholder="Enter Profit" 
                /> 
              </td> 
              <td> 
                <label>Shares</label> 
                <input 
                  type="text" 
                  name="shares" 
                  value={inputs.shares}
                  onChange={handleChange} 
                  placeholder="Enter Shares" 
                /> 
              </td> 
              <td> 
                <label>Funding</label> 
                <input 
                  type="text" 
                  name="funding" 
                  value={inputs.funding} 
                  onChange={handleChange} 
                  placeholder="Enter Funding" 
                /> 
              </td> 
            </tr> 
          </tbody> 
        </table> 
      </div> 
    </div> 
  ); 
}; 
 
export default Page;