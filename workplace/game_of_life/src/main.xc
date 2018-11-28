// COMS20001 - Cellular Automaton Farm

#include <platform.h>
#include <xs1.h>
#include <stdio.h>
#include "pgmIO.h"
#include "i2c.h"
#include <timer.h>

#define  IMHT 16                  //image height
#define  IMWD 16                  //image width

typedef unsigned char uchar;      //using uchar as shorthand

port p_scl = XS1_PORT_1E;         //interface ports to orientation
port p_sda = XS1_PORT_1F;

#define FXOS8700EQ_I2C_ADDR 0x1E  //register addresses for orientation
#define FXOS8700EQ_XYZ_DATA_CFG_REG 0x0E
#define FXOS8700EQ_CTRL_REG_1 0x2A
#define FXOS8700EQ_DR_STATUS 0x0
#define FXOS8700EQ_OUT_X_MSB 0x1
#define FXOS8700EQ_OUT_X_LSB 0x2
#define FXOS8700EQ_OUT_Y_MSB 0x3
#define FXOS8700EQ_OUT_Y_LSB 0x4
#define FXOS8700EQ_OUT_Z_MSB 0x5
#define FXOS8700EQ_OUT_Z_LSB 0x6

in port buttons = XS1_PORT_4E; //port to access xCore-200 buttons
out port leds = XS1_PORT_4F;   //port to access xCore-200 LEDs

#define NO_LEDS             0X0000
#define GREEN_SEPARATE_LED  0x0001
#define GREEN_LED           0x0004
#define BLUE_LED            0x0002
#define RED_LED             0x0008

/////////////////////////////////////////////////////////////////////////////////////////
//
// Read Image from PGM file from path infname[] to channel c_out
//
/////////////////////////////////////////////////////////////////////////////////////////
void dataInStream(char infname[], chanend c_out)
{
  int res;
  uchar line[ IMWD ];

  c_out :> int a;

  printf( "DataInStream: Start...\n" );

  //Open PGM file
  res = _openinpgm( infname, IMWD, IMHT );
  if( res )
  {
    printf( "DataInStream: Error openening %s\n.", infname );
    return;
  }

  //Read image line-by-line and send byte by byte to channel c_out
  for( int y = 0; y < IMHT; y++ )
  {
    _readinline( line, IMWD );
    for( int x = 0; x < IMWD; x++ )
    {
      c_out <: line[ x ];
    }
  }

  //Close PGM image file
  _closeinpgm();
  printf( "DataInStream: Done...\n" );
  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Write pixel stream from channel c_in to PGM image file
//
/////////////////////////////////////////////////////////////////////////////////////////
void dataOutStream(char outfname[], chanend c_in)
{
  int res;
  uchar line[ IMWD ];

  while(1)
  {
      select
      {
          case c_in :> int from_distributor:
              if(from_distributor == 1)
              {
                  //Open PGM file
                  printf( "DataOutStream: Start...\n" );
                  res = _openoutpgm( outfname, IMWD, IMHT );
                  if( res )
                  {
                    printf( "DataOutStream: Error opening %s\n.", outfname );
                    return;
                  }

                  //Compile each line of the image and write the image line-by-line
                  for( int y = 0; y < IMHT; y++ )
                  {
                    for( int x = 0; x < IMWD; x++ )
                    {
                      c_in :> line[ x ];
                    }
                    _writeoutline( line, IMWD );
                    printf( "DataOutStream: Line written to the file...\n" );
                  }

                  //Close the PGM image
                  _closeoutpgm();
                  printf( "DataOutStream: Done...\n" );
              }
              break;
      }

  }

  return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Initialise and  read orientation
// Send every change in tiltness through the channel
//
/////////////////////////////////////////////////////////////////////////////////////////
void orientation( client interface i2c_master_if i2c, chanend toDist)
{
    i2c_regop_res_t result;
    char status_data = 0;
    int tilted = 0;

    // Configure FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_XYZ_DATA_CFG_REG, 0x01);
    if (result != I2C_REGOP_SUCCESS)
    {
        printf("I2C write reg failed\n");
    }

    // Enable FXOS8700EQ
    result = i2c.write_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_CTRL_REG_1, 0x01);
    if (result != I2C_REGOP_SUCCESS)
    {
        printf("I2C write reg failed\n");
    }

    //Probe the orientation x-axis forever
    while (1)
    {
        //check until new orientation data is available
        do {
          status_data = i2c.read_reg(FXOS8700EQ_I2C_ADDR, FXOS8700EQ_DR_STATUS, result);
        } while (!status_data & 0x08);

        //get new x-axis tilt value
        int x = read_acceleration(i2c, FXOS8700EQ_OUT_X_MSB);

        // if the board is now tilted, send to the distributor 1
        if (!tilted && (x>30 || x<-30))
        {
            toDist <: 1;
            tilted = 1 - tilted;
        }
        // if the board is no longer tilted, send to the distributor 0
        if(tilted && (x <= 30 && x>= -30))
        {
            toDist <: 0;
            tilted = 1 - tilted;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Listens for button input and sends it to the distributor
//
/////////////////////////////////////////////////////////////////////////////////////////
void buttonListener(in port b, chanend c_buttons)
{
    int r;

    while (1)
    {
        b when pinseq(15)  :> r;    // check that no button is pressed
        b when pinsneq(15) :> r;    // check if some buttons are pressed
        if ((r==13) || (r==14))     // if either button is pressed
        {
            c_buttons <: r;         // send button pattern to userAnt
        }
    }
    return;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Main timer thread, communicating with the
// client and running concurrently with the helper thread
//
/////////////////////////////////////////////////////////////////////////////////////////
void mainTimerThread(chanend c_helper_timer, chanend c_timer)
{
    unsigned int startTime;
    unsigned int endTime;
    unsigned int nullifier;
    unsigned int numberOfOverflows;
    unsigned long long int resultingTime;
    int fromController;
    int fromHelperTimerThread;
    unsigned int period = 100000000;                      // period of 1 second
    unsigned long long overflowSize = 4294967296LL;   // the length of one overflow

    // We initialize a timer and find the constant
    // which added to it would nullify it
    // This is done to ensure that the two timer threads
    // overflow at the same time (they don't share the same timer)

    timer t;
    t :> startTime;
    nullifier  =  -startTime;
    startTime +=  nullifier;


    while (1)
    {
        select
        {
            case c_helper_timer :> fromHelperTimerThread:
                numberOfOverflows++;
                break;

            case c_timer :> fromController:
                if(fromController == 1)
                {
                    t :> startTime;
                    startTime += nullifier;
                    numberOfOverflows = 0;
                }
                else if(fromController == 2)
                {
                    t :> endTime;
                    endTime += nullifier;

                    if(endTime <= startTime)
                    {
                        numberOfOverflows++;
                    }

                    resultingTime   =   overflowSize;
                    resultingTime  *=   numberOfOverflows;
                    resultingTime  +=   endTime-startTime;
                }
                else if(fromController == 3)
                {
                    // printf("Number of overflows  : %u\n", numberOfCycles);
                    printf("Time passed (raw)    : %llu\n", resultingTime);
                    printf("Time passed (seconds): %f\n", ((double)resultingTime/period));
                    c_timer <: 1;
                }
                break;
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Helper timer thread, which checks continuously for overflows of the timer
//
/////////////////////////////////////////////////////////////////////////////////////////
void helperTimerThread(chanend c_helper_timer)
{
    unsigned int startTime;
    unsigned int currentTime;
    unsigned int nullifier;

    // We initialize a timer and find the constant
    // which added to it would nullify it
    // This is done to ensure that the two timer threads
    // overflow at the same time (they don't share the same timer)

    timer t;
    t :> startTime;
    nullifier  =  -startTime;
    startTime +=  nullifier;

    // Every second we check if the timer has overflowed
    while(1)
    {
        t :> currentTime;
        currentTime += nullifier;
        if(currentTime < startTime)
        {
            c_helper_timer <: 1;
        }
        startTime = currentTime;
        delay_milliseconds(1000);
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Print matrix to the terminal
//
/////////////////////////////////////////////////////////////////////////////////////////
void printMatrix(char matrix[IMHT][IMWD])
{
    printf("Matrix console printing starting.\n");
    for(int a=0;a<IMHT;a++)
    {
        for(int b=0;b<IMWD;b++)
        {
            printf("%c ", (matrix[b][a]+'0'));
        }
        printf("\n");
    }
    printf("\n");
    printf("Matrix console printing ended.\n");
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Calculate next state of a cell based on the number of neighbours
// and its current state
//
/////////////////////////////////////////////////////////////////////////////////////////
char isAlive(int neighbours, char previousState)
{
    if(neighbours == 3)                         return 1;
    if(neighbours == 2 && previousState == 1)   return 1;
    return 0;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Calculate next state
//
/////////////////////////////////////////////////////////////////////////////////////////
void calculateNextState(char matrix[IMHT][IMWD])
{
    char previous[IMHT][IMWD];
    const int neighbourX[8] = {-1,  0, 1, -1, 1, -1,  0, 1};
    const int neighbourY[8] = {-1, -1, -1, 0, 0, 1, 1, 1};
    int numberOfAlive;
    int nX;
    int nY;

    for(int a = 0; a < IMHT; a++)
    {
        for(int b = 0; b < IMWD; b++)
        {
            previous[a][b]=matrix[a][b];
        }
    }

    for(int a = 0; a < IMHT; a++)
    {
        for(int b = 0; b < IMWD; b++)
        {
            numberOfAlive = 0;
            for(int i=0;i<8;i++)
            {
                nX = (b+neighbourX[i]+IMWD)%IMWD;
                nY = (a+neighbourY[i]+IMHT)%IMHT;
                if(previous[nY][nX]) numberOfAlive++;
            }

            matrix[a][b] = isAlive(numberOfAlive, previous[a][b]);
        }
    }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Count number of all live cells
//
/////////////////////////////////////////////////////////////////////////////////////////
int countLiveCells(char matrix[IMHT][IMWD])
{
    int result = 0;

    for( int y = 0; y < IMHT; y++ )
    {
      for( int x = 0; x < IMWD; x++ )
      {
        if(matrix[y][x] == 1) result++;
      }
    }

    return result;
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Function, which implements game of life by farming out parts of the gamestate
// to worker threads which implement it.
//
/////////////////////////////////////////////////////////////////////////////////////////
void distributor(chanend c_in, chanend c_out, chanend c_control, chanend c_timer, chanend c_buttons)
{
  uchar val;
  int   buttonInput;
  char  greenLedState = 1;
  char  matrix[IMHT][IMWD];      // array for the game state
  int   rounds = 0;               // number of passed rounds

  //Starting up and wait for pressing of SW1 button
  printf( "ProcessImage: Start, size = %dx%d\n", IMHT, IMWD );
  printf( "Waiting for press of SW1 button...\n" );

  while(1)
  {
      c_buttons :> buttonInput;
      if(buttonInput == 14) break;
  }

  leds <: GREEN_LED;
  c_in <: 1;
  for( int y = 0; y < IMHT; y++ )       //go through all lines
  {
    for( int x = 0; x < IMWD; x++ )     //go through each pixel per line
    {
      c_in :> val;
      if(val) matrix[y][x] = 1;
      else matrix[y][x] = 0;
    }
  }
  leds <: NO_LEDS;

  printf( "Processing...\n" );

  // printMatrix(matrix);

  c_timer <: 1;

  while(1)
  {
      select
      {
          case c_buttons :> buttonInput:
              if(buttonInput == 13)
              {
                  printf( "Saving to file... \n" );
                  leds  <: BLUE_LED;
                  c_out <: 1;
                  for( int y = 0; y < IMHT; y++ )       // go through all lines
                  {
                    for( int x = 0; x < IMWD; x++ )     // go through each pixel per line
                    {
                        if(matrix[y][x]) c_out <: ((uchar)(0xFF));
                        else c_out <: ((uchar)(0x00));
                    }
                  }
                  leds <: NO_LEDS;
              }
              break;
          case c_control :> int value:
              if(value == 1)
              {
                  c_timer   <: 2;
                  leds      <: RED_LED;
                  printf("=================================\n");
                  printf("Number of rounds     : %d\n", rounds);
                  printf("Number of live cells : %d\n", countLiveCells(matrix));
                  c_timer <: 3;
                  c_timer :> int a;
                  printf("=================================\n");

                  c_control :> value;
                  leds      <: NO_LEDS;

                  printf("Processing restarted.\n");
              }
              break;

          default:
              calculateNextState(matrix);
              rounds++;
              if(greenLedState)
              {
                  leds <: GREEN_SEPARATE_LED;
              }
              else
              {
                  leds <: NO_LEDS;
              }
              greenLedState = 1 - greenLedState;
              // delay_milliseconds(1000);
              break;
      }
  }
}

/////////////////////////////////////////////////////////////////////////////////////////
//
// Orchestrate concurrent system and start up all threads
//
/////////////////////////////////////////////////////////////////////////////////////////
int main(void)
{
    i2c_master_if i2c[1];               // interface to orientation

    char infname[] = "test.pgm";        // input image path
    char outfname[] = "testout.pgm";    // output image path
    chan c_inIO;                        // channel for input file stream
    chan c_outIO;                       // channel for output file stream
    chan c_control;                     // channel for accelerometer
    chan c_timer;                       // channel for main timer
    chan c_helper_timer;                // channel for helper timer thread
    chan c_buttons;                     // channel for buttons listener thread

    par
    {
        dataInStream(infname, c_inIO);              // thread to read in a PGM image
        dataOutStream(outfname, c_outIO);           // thread to write out a PGM image
        i2c_master(i2c, 1, p_scl, p_sda, 10);       // server thread providing orientation data
        orientation(i2c[0],c_control);              // client thread reading orientation data
        buttonListener(buttons, c_buttons);         // thread listening for button action
        mainTimerThread(c_helper_timer, c_timer);   // main timer thread
        helperTimerThread(c_helper_timer);          // thread checking for timer overflow

        distributor(c_inIO, c_outIO, c_control, c_timer, c_buttons);    // thread to coordinate work on image
      }

      return 0;
}
