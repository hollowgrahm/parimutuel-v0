"use client";
import React from "react";
import Link from "next/link";
import { Spotlight } from "../ui/Spotlight";
import { Button } from "../ui/moving-border";
import Blockchains from "../Intro/Blockchains";
import { FlipWords } from "../ui/flip-words";

interface Logo {
  name: string;
  url: string;
}

const logos: Logo[] = [
  {
    name: "Chainlink",
    url: "https://assets-global.website-files.com/5f6b7190899f41fb70882d08/5f760a499b56c47b8fa74fbb_chainlink-logo.svg",
  },
  {
    name: "Solana",
    url: "https://solana.com/_next/static/media/logotype.e4df684f.svg",
  },
  {
    name: "Wormhole",
    url: "https://images.ctfassets.net/n8aw1cra6v98/2057wAXk6apiGi4vfTeC2u/9e200f5dfebaf6bb113c879243cf4508/wormwhole.svg?w=384&q=100",
  },
  {
    name: "Monad",
    url: "https://assets-global.website-files.com/647f71a77a2f4691b4fa23a7/647f71a77a2f4691b4fa23cf_monad-horizontal-logo-inverted-rgb.svg",
  },
];

const words = ["Chainlink", "Solana", "Wormhole", "Monad"];

const HeroSection: React.FC = () => {
  return (
    <>
      <div className="h-auto md:h-[40rem] w-full rounded-md flex flex-col items-center justify-center relative overflow-hidden mx-auto py-10 md:py-0">
        <Spotlight
          className="-top-40 left-0 md:left-60 md:-top-20"
          fill="white"
        />
        <div className="p-4 relative z-10 w-full text-center">
          <div className="mt-20 md:mt-10 text-4xl md:text-7xl font-bold bg-clip-text text-transparent bg-gradient-to-b from-neutral-50 to-neutral-400">
            Build on <FlipWords words={words} />
          </div>
          <p className="mt-4 font-normal text-base md:text-lg text-neutral-300 max-w-lg mx-auto">
          Dive into our comprehensive courses on decentralized exchanges (DEX) and transform your blockchain journey today. Whether you're a beginner or looking to refine your trading skills, join us to unlock your true potential in the world of decentralized finance.
          </p>

          <div className="mt-4">
            <div>
              <Button
                borderRadius="1.75rem"
                className="bg-white dark:bg-slate-900 text-black dark:text-white border-neutral-200 dark:border-slate-800 font-medium"
              >
                Explore
              </Button>
            </div>
          </div>
        </div>

        <div className="w-full py-12 text-white">
          <div className="mx-auto w-full px-4 md:px-8">
            <div
              className="group relative mt-6 flex gap-6 md:gap-12 overflow-hidden p-2"
              style={{
                maskImage:
                  "linear-gradient(to left, transparent 0%, black 20%, black 80%, transparent 95%)",
              }}
            >
              {Array(5)
                .fill(null)
                .map((_, index) => (
                  <div
                    key={index}
                    className="flex shrink-0 animate-logo-cloud flex-row justify-around gap-6 md:gap-12"
                  >
                    {logos.map((logo, key) => (
                      <img
                        key={key}
                        src={logo.url}
                        className="h-8 md:h-9 w-auto px-2 md:px-4 brightness-100 text-white"
                        alt={logo.name}
                      />
                    ))}
                  </div>
                ))}
            </div>
          </div>
        </div>
      </div>

      <div>
        <Blockchains />
      </div>
    </>
  );
};

export default HeroSection;
